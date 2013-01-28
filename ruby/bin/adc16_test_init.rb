#!/usr/bin/env ruby

require 'rubygems'
require 'adc16/test'

raise "\nusage: #{File.basename $0} R2HOSTNAME [BOF]" unless ARGV[0]

bof = ARGV[1] || ADC16Test::DEFAULT_BOF
a = ADC16Test.new(ARGV[0], :bof => bof)

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
