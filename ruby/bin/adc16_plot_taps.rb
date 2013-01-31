#!/usr/bin/env ruby

require 'rubygems'

require 'optparse'

require 'narray'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

OPTS = {
  :chips => (:a..:h).to_a,
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => [4,4],
  :verbose => false,
  :num_iters => 1,
  :expected => 0x2a
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME [BOF]"
  o.separator('')
  o.separator('Plot error counts for various ADC16 delay tap settings.')
  o.separator('Programs FPGA with BOF, if given.')
  o.separator('')
  o.separator 'Options:'
  o.on('-c', '--chips=C,C,...', Array, "Which chips to plot [all]") do |o|
    OPTS[:chips] = o
  end
  o.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  o.on('-e', '--expected=N', "Expected value of deskew pattern [#{OPTS[:expected]}]") do |o|
    OPTS[:expected] = Integer(o) rescue OPTS[:expected]
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
  o.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do
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

a = ADC16.new(ARGV[0])

# Limit chips to those supported by gateware
OPTS[:chips].select! {|c| ADC16.chip_num(c) < a.num_adcs}

if ARGV[1]
  puts "Programming FPGA with #{ARGV[1]}" if OPTS[:verbose]
  a.progdev ARGV[1]
  puts 'Initializing ADC' if OPTS[:verbose]
  a.adc_init
end

def plot_counts(counts, plotopts={})
  plotopts = {
    :line => :line,
    :marker => Marker::STAR,
    :title => 'Error Counts vs Delay Tap',
    :ylabel => 'log2(err_count+1)',
    :xlabel => 'Delay Tap Value',
    :line_color_a => Color::BLUE,
    :line_color_b => Color::RED
  }.merge!(plotopts)
  logcounts=NMath.log2(NArray[*counts].to_f+1)

  plotopts[:line_color] = plotopts[:line_color_a]
  plotopts[:overlay] = false
  plot(logcounts[0,nil], plotopts)

  plotopts[:line_color] = plotopts[:line_color_b]
  plotopts[:overlay] = true
  plot(logcounts[1,nil], plotopts)

  # Add color coded labels for chose tap settings
  pgsci(plotopts[:line_color_a])
  pgmtxt('T', 0.5, 0, 0, "a:#{plotopts[:set_taps][0]}")
  pgsci(plotopts[:line_color_b])
  pgmtxt('T', 0.5, 1, 1, "b:#{plotopts[:set_taps][1]}")

  # Plot circles where only lane a has zero error count
  pgsci(plotopts[:line_color_a])
  good = logcounts[0,nil].eq(0).and(logcounts[1,nil].ne(0)).where
  good.each do |x|
    pgpt1(x, 0, Marker::CIRCLE)
  end

  # Plot circles where only lane b has zero error count
  pgsci(plotopts[:line_color_b])
  good = logcounts[0,nil].ne(0).and(logcounts[1,nil].eq(0)).where
  good.each do |x|
    pgpt1(x, 0, Marker::CIRCLE)
  end

  # Plot points where both lanes have zero error count in green
  pgsci(Color::GREEN)
  good = logcounts[0,nil].eq(0).and(logcounts[1,nil].eq(0)).where
  good.each do |x|
    pgpt1(x, 0, Marker::CIRCLE)
  end
end

OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
plotter=Plotter.new(OPTS)
pgsch(2.5) if OPTS[:nx] > 1 || OPTS[:ny] > 1

puts 'Selecting ADC deskew pattern' if OPTS[:verbose]
a.deskew_pattern
OPTS[:chips].each do |chip|
  set_taps, counts = a.walk_taps(chip, OPTS)
  4.times do |chan|
    title2 = "ADC Channel #{chip}#{chan+1}"
    title2 += " (#{OPTS[:num_iters]} iters)" if OPTS[:num_iters] != 1
    plot_counts(counts[chan], :title2 => title2, :set_taps => set_taps[chan])
  end
end
puts 'Selecting ADC analog inputs' if OPTS[:verbose]
a.no_pattern

plotter.close
