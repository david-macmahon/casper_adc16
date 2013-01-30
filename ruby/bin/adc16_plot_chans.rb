#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

OPTS = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => [4, 4],
  :ask => true,
  :nsamps => 100
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME"
  o.separator('')
  o.separator('Plot time series all ADC16 channels')
  o.separator('')
  o.separator 'Options:'
  o.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  o.on('-l', '--length=N', Integer, "Number of samples to plot (1-1024) [#{OPTS[:nsamps]}]") do |o|
    if ! (1..1024) === o
      STDERR.puts 'length option must be between 1 and 1024, inclusive'
      exit 1
    end
    OPTS[:nsamps] = o
  end
  o.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [#{OPTS[:nxy].join(',')}]") do |o|
    if o.length != 2
      raise OptionParser::InvalidArgument.new('invalid NX,NY')
    end
    OPTS[:nxy] = o.map {|s| Integer(s) rescue 2}
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

a = ADC16.new(ARGV[0])

OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
plot=Plotter.new(OPTS)

#TODO Support second ADC16 board
CHIPS = ['A', 'B', 'C', 'D']

data = a.snap(:a, :b, :c, :d, :n => OPTS[:nsamps])
data.each_with_index do |chip_data, chip_idx|
  4.times do |chan|
    plot(chip_data[chan,nil],
         :line => :stairs,
         :title => "ADC Channel #{CHIPS[chip_idx]}#{chan+1}",
         :ylabel => 'ADC Sample Value',
         :xlabel => 'Sample Number'
        )
  end
end

plot.close
