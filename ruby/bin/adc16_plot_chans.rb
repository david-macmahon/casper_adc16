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

['A', 'B', 'C', 'D'].each do |chip|
  data =a.snap(chip, :n => opts[:nsamps])
  4.times do |chan|
    plot(data[chan,nil],
         :line => :stairs,
         :title => "ADC #{chip} chan #{chan}",
         :ylabel => 'ADC Sample Value',
         :xlabel => 'Sample Number'
        )
  end
end

plot.close
