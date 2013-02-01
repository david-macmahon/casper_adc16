#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'narray'
require 'gsl'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

OPTS = {
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => [1, 1],
  :ask => true,
  :nsamps => 1024,
  :plot_max_line => true,
  :plot_fs4_line => true
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME CHANSPEC"
  op.separator('')
  op.separator('Plot spectrum of a single ADC16 channel (a1, d4, etc.)')
  op.separator('')
  op.separator 'Options:'
  op.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  op.on('-l', '--length=N', Integer, "Number of samples to plot (1-1024) [#{OPTS[:nsamps]}]") do |o|
    if !((1..1024) === o)
      STDERR.puts 'length option must be between 1 and 1024, inclusive'
      exit 1
    end
    OPTS[:nsamps] = o
  end
  op.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [#{OPTS[:nxy].join(',')}]") do |o|
    if o.length != 2
      raise OptionParser::InvalidArgument.new('invalid NX,NY')
    end
    OPTS[:nxy] = o.map {|s| Integer(s) rescue 2}
  end
  op.on_tail("-h", "--help", "Show this message") do
    puts op
    exit 1
  end
end
OP.parse!

if ARGV.length < 2
  STDERR.puts OP
  exit 1
end

raise "\nusage: #{File.basename $0} R2HOSTNAME CHANSPEC" unless ARGV[0] && ARGV[1]

a = ADC16.new(ARGV[0])
chip, chan = ADC16.chip_chan(ARGV[1])

OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
plot=Plotter.new(OPTS)
pgsch(2.5) if OPTS[:nx] > 1 || OPTS[:ny] > 1

#100.times do
  data = a.snap(chip, :n => OPTS[:nsamps])

  spec_amp = data[chan-1,nil].to_gv.forward!.hc_amp_phase[0].abs

  plot(spec_amp,
       :line => :stairs,
       :title => "ADC Channel #{chip.upcase}#{chan}",
       :ylabel => 'Amplitude',
       :xlabel => 'Frequency Channel'
      )

  pgsls(Line::DASHED)

  if OPTS[:plot_max_line]
    plot([0, OPTS[:nsamps]/2+1], [spec_amp.max]*2,
         :line_color => Color::WHITE,
         :overlay => true)
  end

  if OPTS[:plot_fs4_line]
    plot([OPTS[:nsamps]/4]*2, [0, spec_amp.max*2],
         :line_color => Color::WHITE,
         :overlay => true)
  end

  pgsls(Line::SOLID)

#  sleep 0.1
#end

plot.close
