#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16/test'

OPTS = {
  :nsamps => (1<<16),
  :verbose => false
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME"
  o.separator('')
  o.separator('Dump samples from ADC16 test design')
  o.separator('')
  o.separator 'Options:'
  o.on('-l', '--length=N', Integer, "Number of samples to dump per channel [#{OPTS[:nsamps]}]") do |o|
    OPTS[:nsamps] = o
  end
  o.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do |o|
    OPTS[:verbose] = o
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

a = ADC16Test.new(ARGV[0])

tic = Time.now
# TODO Snap all chips available (e.g. both ADC16 boards)
data = a.snap_test(:a, :b, :c, :d, :n => OPTS[:nsamps])
toc = Time.now
$stderr.puts "data snap took #{toc-tic} seconds" if OPTS[:verbose]

fmt = (['%4d'] * 16).join(' ') + "\n"

tic = Time.now
OPTS[:nsamps].times do |i|
  printf(fmt,
         data[0][0,i], data[0][1,i], data[0][2,i], data[0][3,i],
         data[1][0,i], data[1][1,i], data[1][2,i], data[1][3,i],
         data[2][0,i], data[2][1,i], data[2][2,i], data[2][3,i],
         data[3][0,i], data[3][1,i], data[3][2,i], data[3][3,i],
        )
end
toc = Time.now
$stderr.puts "data dump took #{toc-tic} seconds" if OPTS[:verbose]
