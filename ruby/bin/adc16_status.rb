#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16'

OPTS = {
  :cal_status => false,
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME [...]"
  op.separator('')
  op.separator('Shows ADC16 status for a running ADC16-based design.')
  op.separator('')
  op.separator('Using the --cal option will verify SERDES calibration,')
  op.separator('which will briefly switch in test patterns then revert')
  op.separator('to analog inputs.  For cal status: "." = OK; "X" = BAD.')
  op.separator('')
  op.separator 'Options:'
  op.on('-c', '--[no-]cal', "Check SERDES calibration [#{OPTS[:cal_status]}]") do |o|
    OPTS[:cal_status] = o
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

def check_cal(adc16, nadcs)
  chips_to_snap = (0...nadcs).to_a
  # Check deskew
  adc16.deskew_pattern
  deskew = adc16.snap(chips_to_snap)
  deskew_errors = deskew.map do |na|
    na.ne(0x2a).to_type(NArray::INT).sum(1).to_a
  end
  # Check sync
  adc16.sync_pattern
  sync = adc16.snap(chips_to_snap)
  sync_errors = sync.map do |na|
    na.ne(0x2a).to_type(NArray::INT).sum(1).to_a
  end

  [deskew_errors, sync_errors]
end

ARGV.each do |host|
  a = ADC16.new(host)

  # Make sure FPGA is programmed
  if ! a.programmed?
    puts "#{host}: FPGA not programmed"
    next
  end

  # Make sure it is an adc16-based design
  if a.listdev.grep('adc16_controller').empty?
    puts "#{host}: ADC16 controller device not found"
    next
  end

  # Print status
  r2rev = a.roach2_rev
  nadcs = a.num_adcs
  locked = a.locked_status
  lock0  = (locked & 1) == 1
  lock1  = (locked & 2) == 2
  puts "#{host}: Design built for ROACH2 rev#{r2rev} with #{nadcs} ADCs"
  print "#{host}: ZDOK0 clock #{lock0 ? 'OK' : 'BAD'}"
  if !lock0
    puts
    next
  end
  if nadcs > 4
    print ", ZDOK1 clock #{lock1 ? 'OK' : 'BAD'}"
    nadcs = 4 unless lock1 # Give up checking ZDOK1 ADCs if no/bad clock
  end

  if !OPTS[:cal_status]
    puts
  else
    puts
    # Print cal header
    chip_hdr = (0...nadcs).map{|i| (?A.ord+i).chr * 4}.join('')
    chan_hdr = '1234' * nadcs
    puts "#{host}: #{chip_hdr}"
    puts "#{host}: #{chan_hdr}"
    # Print deskew cal info
    print "#{host}: "
    a.deskew_pattern
    ds=a.snap(*(0...nadcs).to_a)
    ds.each_with_index do |d, chip|
      print(d.ne(0x2a).to_type(NArray::INT).sum(1).to_a.map {|n| n == 0 ? '.' : 'X'}.join(''))
    end
    puts " deskew"
    # Print sync cal info
    print "#{host}: "
    a.sync_pattern
    ds=a.snap(*(0...nadcs).to_a)
    ds.each_with_index do |d, chip|
      print(d.ne(0x70).to_type(NArray::INT).sum(1).to_a.map {|n| n == 0 ? '.' : 'X'}.join(''))
    end
    puts " sync"
    # Select analog inputs
    a.no_pattern
  end
end

__END__
puts "Programming #{ARGV[0]} with #{bof}..."
a.progdev(bof)

puts "Resetting ADC, power cycling ADC, and reprogramming FPGA..."
a.adc_init

# TODO Decode and print status bits

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
