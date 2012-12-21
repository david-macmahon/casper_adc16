#!/usr/bin/env ruby

require 'rubygems'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

# TODO Get these from command line
opts = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nx => 4,
  :ny => 4,
  :ask => true,
  :nsamps => 100
}

raise "\nusage: #{File.basename $0} R2HOSTNAME" unless ARGV[0]

a = ADC16.new(ARGV[0])

plot=Plotter.new(opts)

CHIPS = ['A', 'B', 'C', 'D']

data = a.snap(:a, :b, :c, :d, :n => opts[:nsamps])
data.each_with_index do |chip_data, chip_idx|
  4.times do |chan|
    plot(chip_data[chan,nil],
         :line => :stairs,
         :title => "ADC #{CHIPS[chip_idx]} chan #{chan}",
         :ylabel => 'ADC Sample Value',
         :xlabel => 'Sample Number'
        )
  end
end

plot.close
