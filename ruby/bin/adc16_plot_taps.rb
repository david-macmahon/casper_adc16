#!/usr/bin/env ruby

require 'rubygems'

require 'optparse'

require 'narray'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

# TODO Get these from command line
OPTS = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => [4,4],
  :verbose => false,
  :num_iters => 1
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME"
  o.separator('')
  o.separator('Plot error counts for various ADC16 delay tap settings.')
  o.separator('')
  o.separator 'Options:'
  o.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  o.on('-i', '--iters=N', Integer, "Number of snaps per tap [#{OPTS[:num_iters]}]") do |o|
    OPTS[:num_iters] = o
  end
  o.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [#{OPTS[:nxy].join(',')}]") do |o|
    if o.length != 2
      raise OptionParser::InvalidArgument.new('invalid NX,NY')
    end
    OPTS[:nxy] = o.map {|s| Integer(s) rescue 2}
  end
  o.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:nxy].join(',')}]") do
    OPTS[:verbose] = OPTS[:verbose] ? :very : true
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

  # Plot points where both lanes have zero error count in green
  pgsci(Color::GREEN)
  good = logcounts[0,nil].eq(0).and(logcounts[1,nil].eq(0)).where
  good.each do |x|
    pgpt1(x, 0, Marker::CIRCLE)
  end
end

OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
plotter=Plotter.new(OPTS)

a.deskew_pattern
['A', 'B', 'C', 'D'].each do |chip|
  good, counts = a.walk_taps(chip, OPTS)
  4.times do |chan|
    title2 = "ADC Channel #{chip}#{chan+1}"
    title2 += " (#{OPTS[:num_iters]} iters)" if OPTS[:num_iters] != 1
    plot_counts(counts[chan], :title2 => title2)
  end
end
a.no_pattern

plotter.close
