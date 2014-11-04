#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16'

OPTS = {
  :nsamps => 1024,
  :rms => false,
  :test => false,
  :verbose => false
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME"
  op.separator('')
  op.separator('Dump samples from ADC16 based design.')
  op.separator('Lengths between 1025 and 65536 requires the adc16_test design.')
  op.separator('')
  op.separator 'Options:'
  op.on('-l', '--length=N', Integer, "Number of samples to dump per channel (1-65536) [#{OPTS[:nsamps]}]") do |o|
    if (1025..65536) === o
      OPTS[:test] = true
    elsif ! ((1..1024) === o)
      STDERR.puts 'length option must be between 1 and 65536, inclusive'
      exit 1
    end
    OPTS[:nsamps] = o
  end
  op.on('-r', '--rms', "Output RMS of each channel instead of raw samples [#{OPTS[:rms]}]") do |o|
    OPTS[:rms] = o
  end
  op.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do |o|
    OPTS[:verbose] = o
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

if OPTS[:test]
  require 'adc16/test'
  adc16_class = ADC16Test
  snap_method = :snap_test
  device_check = 'snap_a_bram'
else
  adc16_class = ADC16
  snap_method = :snap
  device_check = 'adc16_controller'
end

def dump_samples(data)
  ncols = data[0].shape[0]
  fmt = ' %4d' * ncols
  tic = Time.now
  OPTS[:nsamps].times do |i|
    data.each_with_index do |d, j|
      printf(j > 0 ? fmt : fmt[1..-1], *data[j][nil,i])
    end
    puts
  end
  toc = Time.now
  $stderr.puts "data dump took #{toc-tic} seconds" if OPTS[:verbose]
end

def dump_rms(data)
  rms = data.map {|na| na.rms(1).to_a}
  rms.flatten!
  fmt = (['%4.1f'] * (rms.length)).join(' ') + "\n"
  printf(fmt, *rms)
end

a = adc16_class.new(ARGV[0])

# Verify suitability of current design
if !a.programmed?
  $stderr.puts 'FPGA not programmed'
  exit 1
elsif a.listdev.grep(device_check).empty?
  $stderr.puts "FPGA is not programmed with an appropriate #{adc16_class} design"
  exit 1
end

tic = Time.now
snap_args = (0...a.num_adcs).to_a
snap_args << {:n => OPTS[:nsamps]}
data = a.send(snap_method, *snap_args)
toc = Time.now
$stderr.puts "data snap took #{toc-tic} seconds" if OPTS[:verbose]

if OPTS[:rms]
  dump_rms(data)
else
  dump_samples(data)
end
