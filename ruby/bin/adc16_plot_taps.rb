#!/usr/bin/env ruby

require 'rubygems'

require 'optparse'

require 'narray'
require 'adc16'

begin
  require 'pgplot/plotter'
rescue LoadError
  $stderr.puts 'Unable to load the pgplotter gem.'
  $stderr.puts 'You can install it by running "gem install pgplotter".'
  exit 1
end
include Pgplot

OPTS = {
  :chips => ('a'..'h').to_a,
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => nil,
  :verbose => false,
  :num_iters => 1,
  :expected => 0x2a
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME [BOF]"
  op.separator('')
  op.separator('Plot error counts for various ADC16 delay tap settings.')
  op.separator('Programs FPGA with BOF, if given.')
  op.separator('')
  op.separator 'Options:'
  op.on('-c', '--chips=C,C,...', Array, "Which chips to plot [all]") do |o|
    OPTS[:chips] = o
  end
  op.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  op.on('-e', '--expected=N', "Expected value of deskew pattern [#{OPTS[:expected]}]") do |o|
    OPTS[:expected] = Integer(o) rescue OPTS[:expected]
  end
  op.on('-i', '--iters=N', Integer, "Number of snaps per tap [#{OPTS[:num_iters]}]") do |o|
    OPTS[:num_iters] = o
  end
  op.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [auto]") do |o|
    if o.length != 2
      raise OptionParser::InvalidArgument.new('invalid NX,NY')
    end
    OPTS[:nxy] = o.map {|s| Integer(s) rescue 2}
  end
  op.on('-v', '--[no-]verbose', "Display more info [#{OPTS[:verbose]}]") do
    OPTS[:verbose] = OPTS[:verbose] ? :very : true
  end
  op.on_tail("-h", "--help", "Show this message") do
    puts op
    exit 1
  end
end
OP.parse!

if ARGV.empty?
  STDERR.puts OP
  exit 1
end

a = ADC16.new(ARGV[0])

# If BOF file given
if ARGV[1]
  puts "Programming FPGA with #{ARGV[1]}" if OPTS[:verbose]
  a.progdev ARGV[1]
  # Verify that programming succeeded
  if ! a.programmed?
    puts "error programming #{ARGV[0]} with #{ARGV[1]}"
    exit 1
  end
  # Verify that given design is ADC16-based
  if ! a.listdev.grep('adc16_controller').any?
    puts "Programmed #{ARGV[0]} with #{ARGV[1]}, but it is not an ADC16-based design."
    exit 1
  end
  # Initialize ADC
  puts 'Initializing ADC' if OPTS[:verbose]
  a.adc_init

# Else BOF file not given, verify host is already programmed with ADC16 design.
elsif ! (a.programmed? && a.listdev.grep('adc16_controller').any?)
  puts "#{ARGV[0]} is not programmed with an ADC16 design."
  exit 1
end

# Limit chips to those supported by gateware
OPTS[:chips] = OPTS[:chips].select {|c| ADC16.chip_num(c) < a.num_adcs}

if OPTS[:nxy]
  OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
else
  OPTS[:nx], OPTS[:ny] = case OPTS[:chips].length
                         when 1; [2, 2]
                         when 2; [4, 2]
                         when 3; [4, 3]
                         else; [4, 4]
                         end
end

def plot_counts(counts, plotopts={})
  plotopts = {
    :line => :line,
    :marker => Marker::STAR,
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

plotter=Plotter.new(OPTS)
pgsch(2.0) if OPTS[:nx] * OPTS[:ny] > 2
pgsch(2.5) if OPTS[:nx] * OPTS[:ny] > 6

puts 'Selecting ADC deskew pattern' if OPTS[:verbose]
a.deskew_pattern
OPTS[:chips].each do |chip|
  set_taps, counts = a.walk_taps(chip, OPTS)
  4.times do |chan|
    title  = "#{ADC16.chip_name(chip)}#{chan+1} Error Counts vs Delay Tap"
    title2 = "#{512*OPTS[:num_iters]} samples/lane"
    plot_counts(counts[chan],
                :title  => title,
                :title2 => title2,
                :set_taps => set_taps[chan])
  end
end
puts 'Selecting ADC sync pattern' if OPTS[:verbose]
a.sync_chips(OPTS)
puts 'Selecting ADC analog inputs' if OPTS[:verbose]
a.no_pattern

plotter.close
