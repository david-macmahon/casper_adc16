#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

OPTS = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => [1, 1],
  :ask => true,
  :nsamps => 100
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME CHANSPEC"
  o.separator('')
  o.separator('Plot time series of a single ADC16 channel (a1, d4, etc.)')
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

if ARGV.length < 2
  STDERR.puts OP
  exit 1
end

a = ADC16.new(ARGV[0])
chip, chan = /^([A-Da-d])([1-4])$/.match(ARGV[1]).captures
raise "\nCHANSPEC must be X#, where X is A-D and # is 1-4" unless chan
chan = chan.to_i

OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
plot=Plotter.new(OPTS)

# TODO Support second ADC board
CHIPS = ['A', 'B', 'C', 'D']

data = a.snap(chip, :n => OPTS[:nsamps])
plot(data[chan-1,nil],
     :line => :stairs,
     :title => "ADC Channel #{chip.upcase}#{chan}",
     :ylabel => 'ADC Sample Value',
     :xlabel => 'Sample Number'
    )

plot.close
