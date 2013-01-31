#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
require 'adc16'
require 'pgplot/plotter'
include Pgplot

OPTS = {
  :chans => (:a..:h).map {|chip| (1..4).map {|chan| "#{chip}#{chan}"}}.flatten,
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => nil,
  :ask => true,
  :nsamps => 100
}

OP = OptionParser.new do |o|
  o.program_name = File.basename($0)

  o.banner = "Usage: #{o.program_name} [OPTIONS] ROACH2_NAME"
  o.separator('')
  o.separator('Plot time series ADC16 channels')
  o.separator('')
  o.separator 'Options:'
  o.on('-c', '--chans=CN,CN,...', Array, "Which channels to plot [all]") do |o|
    OPTS[:chans] = o
  end
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
  o.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [auto]") do |o|
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

# Chip chans will contain chip numbers for keys whose corresponding value is an
# Array of channels to plot for that chip.
chip_chans = {}
num_chans = 0
OPTS[:chans].each do |chan_name|
  chip, chan = ADC16.chip_chan(chan_name) rescue nil
  next unless chip
  chip = ADC16.chip_num(chip) rescue nil
  next if chip.nil? || chip >= a.num_adcs
  chip_chans[chip] ||= []
  chip_chans[chip] << chan
  num_chans += 1
end

if chip_chans.empty?
  puts "No valid channels to plot in [#{OPTS[:chans].join(',')}]."
  exit 1
end

if OPTS[:nxy]
  OPTS[:nx], OPTS[:ny] = OPTS[:nxy]
else
  OPTS[:nx], OPTS[:ny] = case num_chans
                         when 1; [1, 1]
                         when 2; [2, 1]
                         when 3..4; [2, 2]
                         when 5..6; [3, 2]
                         when 7..9; [3, 3]
                         when 10..12; [4, 3]
                         else; [4, 4]
                         end
end

plot=Plotter.new(OPTS)
pgsch(2.0) if OPTS[:nx] * OPTS[:ny] > 2
pgsch(2.5) if OPTS[:nx] * OPTS[:ny] > 6

#TODO Support second ADC16 board
CHIP_NAMES = ('A'..'H').to_a

chips = chip_chans.keys.sort
data = a.snap(*chips, :n => OPTS[:nsamps])
# Make sure data is an array of NArrays, even if only one element
data = [data].flatten
# Plot data
data.each_with_index do |chip_data, chips_idx|
  chip_num = chips[chips_idx]
  chip_chans[chip_num].each do |chan|
    plot(chip_data[chan-1,nil],
         :line => :stairs,
         :title => "ADC Channel #{CHIP_NAMES[chip_num]}#{chan}",
         :ylabel => 'ADC Sample Value',
         :xlabel => 'Sample Number'
        )
  end
end

plot.close
