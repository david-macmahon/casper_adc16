#!/usr/bin/env ruby

require 'rubygems'
require 'adc16'

# TODO Get these from command line
opts = {
  :nsamps => (1<<4)
}

raise "\nusage: #{File.basename $0} R2HOSTNAME" unless ARGV[0]

a = ADC16.new(ARGV[0])

data = ['A', 'B', 'C', 'D'].map do |chip|
  a.snap(chip, :n => opts[:nsamps])
end

fmt = (['%4d'] * 16).join(' ') + "\n"

opts[:nsamps].times do |i|
  4.times do |adc|
    4.times do |chan|
      print ' ' unless adc==0 && chan==0
      printf '%4d', data[adc][chan,i]
    end
  end
  puts
end
