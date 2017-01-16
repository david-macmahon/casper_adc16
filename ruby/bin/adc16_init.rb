#!/usr/bin/env ruby

require 'optparse'

OPTS = {
  :gain => nil,
  :init_regs => {},
  :verbose => false,
  :num_iters => 1,
  :demux_mode => 1,
  :protocol => ENV['ADC16_PROTOCOL'] || 'katcp'
}

GAINS = %w{ 1 1.25 2 2.5 4 5 8 10 12.5 16 20 25 32 50 }

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [-P katcp] [OPTIONS] HOSTNAME BOF\n" +
              "       #{op.program_name} [-P tapcp] [OPTIONS] HOSTNAME"
  op.separator('')
  op.separator('In katcp mode: Programs HOSTNAME with ADC16-based design BOF')
  op.separator('               and then calibrates the serdes receivers.')
  op.separator('')
  op.separator('In tapcp mode: Just calibrates the serdes receivers.')
  op.separator('')
  op.separator('In addition to the -P option, the environment variable')
  op.separator('"ADC16_PROTOCOL" can be set to the desired protocol.')
  op.separator('')
  op.separator 'Options:'
  op.on('-d', '--demux=D', ['1', '2', '4'],
        "Set demux mode (1|2|4) [#{OPTS[:demux_mode]}]") do |o|
    OPTS[:demux_mode] = o.to_i
  end
  op.on('-g', '--gain=G', GAINS, "Set digital gain [1]") do |o|
    OPTS[:gain] = GAINS.index(o)
  end
  op.on('-i', '--iters=N', Integer,
        "Number of snaps per tap [#{OPTS[:num_iters]}]") do |o|
    OPTS[:num_iters] = o
  end
  op.on('-P', '--protocol=PROTO', ['katcp', 'tapcp'],
        "Select communication protocol [#{OPTS[:protocol]}]") do |o|
    OPTS[:protocol] = o
  end
  op.on('-r', '--reg=R1=V1[,R2=V2...]', Array,
        'Register addr=value pairs to set') do |o|
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

nargs = OPTS[:protocol] == 'katcp' ? 2 : 1

if ARGV.length != nargs
  STDERR.puts "Need #{nargs} non-option arguments, but #{ARGV.length} given."
  STDERR.puts
  STDERR.puts OP
  exit 1
end

require "adc16/#{OPTS[:protocol]}"

host = ARGV[0]
bof  = ARGV[1]

puts "Connecting to #{host}..."
a = ADC16.new(:remote_host => host, :bof => bof, :verbose => OPTS[:verbose])

if bof
  puts "Programming #{host} with #{bof}..."
  a.progdev(bof)

  # Verify that programming succeeded
  if ! a.programmed?
    puts "error programming #{host} with #{bof}"
    exit 1
  end
end

# Verify that given design is ADC16-based
if a.listdev.grep(/^adc16_controller/).empty?
  puts "Host #{host} is not running an ADC16-based design."
  exit 1
end

# Decode and print build info bits
zdrev = a.zdok_rev
r2rev = a.roach2_rev
nadcs = a.num_adcs
# TODO Fix this hard-coded "ROACH2"
puts "Design built for ROACH2 rev#{r2rev} with #{nadcs} ADCs (ZDOK rev#{zdrev})"

# Check demux mode support and request
demux_mode = OPTS[:demux_mode]
print "Gateware "
if a.supports_demux?
  puts "supports demux modes (using demux by #{demux_mode})"

  # Point channels to input 2 and 4 for demux-by-2 mode unless the user is
  # explicitly setting these registers from the command line.
  if demux_mode == ADC16::DEMUX_BY_2  \
  && !OPTS[:init_regs].has_key?(0x3a) \
  && !OPTS[:init_regs].has_key?(0x3b)
    puts "For demux by 2, will point all channel 0 to input 0, channel 1 to input 2"
    OPTS[:init_regs][0x3a] = 0x0202
    OPTS[:init_regs][0x3b] = 0x0808
  end

  # Point all channels to input 2 for demux-by-4 mode unless the user is
  # explicitly setting these registers from the command line.
  if demux_mode == ADC16::DEMUX_BY_4  \
  && !OPTS[:init_regs].has_key?(0x3a) \
  && !OPTS[:init_regs].has_key?(0x3b)
    puts "For demux by 4, will point all channels to input 2"
    OPTS[:init_regs][0x3a] = 0x0404
    OPTS[:init_regs][0x3b] = 0x0404
  end
else
  puts "does not support demux modes"
  if demux_mode != 1
    raise "cannot use demux by #{demux_mode} with this gateware design"
  end
  demux_mode = ADC16::DEMUX_BY_1
end

# Setup registers for demux_mode (if other than DEMUX_BY_1)
if demux_mode != ADC16::DEMUX_BY_1
  # See if user wants to program bits in reg 0x31
  reg31 = OPTS[:init_regs][0x31] || 0
  # Mask off any existing channel_num bits
  reg31 &= ~7
  # Set the channel_num bits to 2 (demux by 2) or 1 (demux by 4)
  reg31 |= 2 if demux_mode == ADC16::DEMUX_BY_2
  reg31 |= 1 if demux_mode == ADC16::DEMUX_BY_4
  # Save the new reg31 value
  OPTS[:init_regs][0x31] = reg31
end

# Print user-requested register settings
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
if !lock0
  puts "ADC0 clock not locked, unable to proceed."
  exit 1
end
if nadcs > 4 && !lock1
  puts "ADC1 clock not locked, not calibrating chips E,F,G,H"
  # Only calibrate chips A through D
  OPTS[:chips] = [:a, :b, :c, :d]
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

if OPTS[:gain]
  puts "Setting digital gain to #{GAINS[OPTS[:gain]]}..."
  case demux_mode
  when ADC16::DEMUX_BY_1
    a.setreg(0x2a, OPTS[:gain] * 0x1111)
  when ADC16::DEMUX_BY_2
    a.setreg(0x2b, OPTS[:gain] * 0x0011)
  when ADC16::DEMUX_BY_4
    a.setreg(0x2b, OPTS[:gain] * 0x0100)
  end
else
  puts 'Using default digital gain of 1...'
end

if demux_mode != ADC16::DEMUX_BY_1
  puts "Setting demux by #{demux_mode} mode..."
  a.demux = demux_mode
end

a.close

puts "Done!"
