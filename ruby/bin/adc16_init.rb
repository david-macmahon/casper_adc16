#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16/test'

raise "\nusage: #{File.basename $0} R2HOSTNAME [BOF]" unless ARGV[0]
OPTS = {
  :verbose => false,
  :num_iters => 4,
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME [BOF]"
  o.separator('')
  o.separator('Programs an ADC16-based design and calibrates the serdes receivers.')
  o.separator("If BOF is not given, uses #{ADC16Test::DEFAULT_BOF}.")
  o.separator('')
  o.separator 'Options:'
  o.on('-i', '--iters=N', Integer, "Number of snaps per tap [#{OPTS[:num_iters]}]") do |o|
    OPTS[:num_iters] = o
  end
  o.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do
    OPTS[:verbose] = OPTS[:verbose] ? :very : true
  end
  o.on_tail("-h", "--help", "Show this message") do
    puts o
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

puts "Resetting ADC, power cycling ADC, and reprogramming FPGA..."
a.adc_init

# Decode and print status bits
r2rev = a.roach2_rev
nadcs = a.num_adcs
locked = a.locked_status
lock0  = (locked & 1) == 1
lock1  = (locked & 2) == 2
print "Design built for ROACH2 rev#{r2rev} with #{nadcs} ADCs"
print ", ZDOK0 clock #{lock0 ? 'OK' : 'BAD'}"
print ", ZDOK1 clock #{lock1 ? 'OK' : 'BAD'}" if nadcs > 4
puts
if !lock0 || (nadcs > 4 && !lock1)
  puts "ADC clock(s) not locked, unable to proceed."
  exit 1
end

puts "Calibrating SERDES blocks..."
status = a.calibrate(OPTS)
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
