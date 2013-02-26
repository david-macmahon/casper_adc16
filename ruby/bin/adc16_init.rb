#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16/test'

OPTS = {
  :init_regs => {},
  :verbose => false,
  :num_iters => 1,
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME [BOF]"
  op.separator('')
  op.separator('Programs an ADC16-based design and calibrates the serdes receivers.')
  op.separator("If BOF is not given, uses #{ADC16Test::DEFAULT_BOF}.")
  op.separator('')
  op.separator 'Options:'
  op.on('-i', '--iters=N', Integer, "Number of snaps per tap [#{OPTS[:num_iters]}]") do |o|
    OPTS[:num_iters] = o
  end
  op.on('-r', '--reg=R1=V1[,R2=V2...]', Array, 'Register addr=value pairs to set') do |o|
    o.each do |rv|
      reg, val = rv.split('=').map {|s| Integer(s)}
      next unless val
      OPTS[:init_regs][reg] = val
    end
  end
  op.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do
    OPTS[:verbose] = OPTS[:verbose] ? :very : true
  end
  op.on_tail("-h", "--help", "Show this message") do
    puts op
    exit 1
  end
end
OP.parse!

if ARGV.empty?
  STDERR.puts OP
  exit 1
end

bof = ARGV[1] || ADC16Test::DEFAULT_BOF
a = ADC16.new(ARGV[0], :bof => bof)

puts "Programming #{ARGV[0]} with #{bof}..."
a.progdev(bof)

# Verify that programming succeeded
if ! a.programmed?
  puts "error programming #{ARGV[0]} with #{bof}"
  exit 1
end
# Verify that given design is ADC16-based
if ! a.listdev.grep('adc16_controller').any?
  puts "Programmed #{ARGV[0]} with #{bof}, but it is not an ADC16-based design."
  exit 1
end

# Decode and print build info bits
r2rev = a.roach2_rev
nadcs = a.num_adcs
puts "Design built for ROACH2 rev#{r2rev} with #{nadcs} ADCs"

# Prent user-requested register settings
OPTS[:init_regs].keys.sort.each do |reg|
  val = OPTS[:init_regs][reg]
  printf "Will set ADC register 0x%02x to 0x%04x\n", reg, val
end

print "Resetting ADC, "
print "setting registers, " unless OPTS[:init_regs].empty?
puts  "power cycling ADC, and reprogramming FPGA..."
a.adc_init(OPTS[:init_regs])

# Decode and print clock status bits
locked = a.locked_status
lock0  = (locked & 1) == 1
lock1  = (locked & 2) == 2
print   "ZDOK0 clock #{lock0 ? 'OK' : 'BAD'}"
print ", ZDOK1 clock #{lock1 ? 'OK' : 'BAD'}" if nadcs > 4
puts
if !lock0 || (nadcs > 4 && !lock1)
  puts "ADC clock(s) not locked, unable to proceed."
  exit 1
end

print "Calibrating SERDES blocks..."
status = a.calibrate(OPTS) {|chip| print chip unless OPTS[:verbose]}
puts

# If any status is false
if status.index(false)
  ('A'..'H').each_with_index do |adc, i|
    break if i >= status.length
    puts "ERROR: SERDES calibration failed for ADC #{adc}." unless status[i]
  end
else
  puts 'SERDES calibration successful.'
end

puts "Selecting analog inputs..."
a.no_pattern

puts "Done!"
