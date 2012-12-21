#!/usr/bin/env ruby

require 'rubygems'
require 'narray'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

# TODO Get these from command line
opts = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nx => 4,
  :ny => 4
}

raise "\nusage: #{File.basename $0} R2HOSTNAME" unless ARGV[0]

a = ADC16.new(ARGV[0])

def plot_counts(counts, plotopts={})
  plotopts = {
    :line => :none,
    :marker => Marker::STAR,
    :title => 'Error Counts vs Delay Tap',
    :ylabel => 'log2(err_count+1)',
    :xlabel => 'Delay Tap Value'
  }.merge!(plotopts)
  logcounts=NMath.log2(NArray[*counts].to_f+1)
  plotopts[:overlay] = false
  plot(logcounts[0,nil], plotopts)
  plotopts[:overlay] = true
  plot(logcounts[1,nil], plotopts)
end

plot=Plotter.new(opts)

a.deskew_pattern
['A', 'B', 'C', 'D'].each do |chip|
  good, counts = a.walk_taps(chip)
  4.times do |chan|
    title2 = "ADC Channel #{chip}#{chan+1}"
    plot_counts(counts[chan], :title2 => title2)
  end
end
a.no_pattern

plot.close
