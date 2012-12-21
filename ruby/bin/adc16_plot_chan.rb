#!/usr/bin/env ruby

require 'rubygems'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

# TODO Get these from command line
opts = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nx => 1,
  :ny => 1,
  :ask => true,
  :nsamps => 100
}

raise "\nusage: #{File.basename $0} R2HOSTNAME CHANSPEC" unless ARGV[0] && ARGV[1]

a = ADC16.new(ARGV[0])
chip, chan = /^([A-Da-d])([1-4])$/.match(ARGV[1]).captures
raise "\nCHANSPEC must be X#, where X is A-D and # is 1-4" unless chan
chan = chan.to_i

plot=Plotter.new(opts)

CHIPS = ['A', 'B', 'C', 'D']

data = a.snap(chip, :n => opts[:nsamps])
plot(data[chan-1,nil],
     :line => :stairs,
     :title => "ADC Channel #{chip.upcase}#{chan}",
     :ylabel => 'ADC Sample Value',
     :xlabel => 'Sample Number'
    )

plot.close
