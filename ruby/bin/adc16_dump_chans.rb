#!/usr/bin/env ruby

require 'rubygems'
require 'adc16/test'

# TODO Get these from command line
opts = {
  :nsamps => (1<<16),
  :verbose => false
}

raise "\nusage: #{File.basename $0} R2HOSTNAME" unless ARGV[0]

a = ADC16Test.new(ARGV[0])

tic = Time.now
data = a.snap_test(:a, :b, :c, :d, :n => opts[:nsamps])
toc = Time.now
$stderr.puts "data snap took #{toc-tic} seconds" if opts[:verbose]

fmt = (['%4d'] * 16).join(' ') + "\n"

tic = Time.now
opts[:nsamps].times do |i|
  printf(fmt,
         data[0][0,i], data[0][1,i], data[0][2,i], data[0][3,i],
         data[1][0,i], data[1][1,i], data[1][2,i], data[1][3,i],
         data[2][0,i], data[2][1,i], data[2][2,i], data[2][3,i],
         data[3][0,i], data[3][1,i], data[3][2,i], data[3][3,i],
        )
end
toc = Time.now
$stderr.puts "data dump took #{toc-tic} seconds" if opts[:verbose]
