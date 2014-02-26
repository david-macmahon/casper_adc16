#!/usr/bin/env ruby

require 'rubygems'
require 'optparse'
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
  :chans => (:a..:h).map {|chip| (1..4).map {|chan| "#{chip}#{chan}"}}.flatten,
  :device => ENV['PGPLOT_DEV'] || '/xs',
  :nxy => nil,
  :ask => true,
  :nsamps => 100,
  :stats => true,
  :test => false,
  :type => :time
}

OP = OptionParser.new do |op|
  op.program_name = File.basename($0)

  op.banner = "Usage: #{op.program_name} [OPTIONS] ROACH2_NAME"
  op.separator('')
  op.separator('Plot time series ADC16 channels.')
  op.separator('Lengths between 1025 and 65536 requires the adc16_test design.')
  op.separator('')
  op.separator 'Options:'
  op.on('-c', '--chans=CN,CN,...', Array, "Which channels to plot [all]") do |o|
    OPTS[:chans] = o
  end
  op.on('-d', '--device=DEV', "Plot device to use [#{OPTS[:device]}]") do |o|
    OPTS[:device] = o
  end
  op.on('-F', '--[no-]freq', "Plot frequency channels (-t freq)") do |o|
    OPTS[:type] = :freq
  end
  op.on('-H', '--[no-]histo', "Plot histogram (-t histo)") do |o|
    OPTS[:type] = :histo
  end
  op.on('-l', '--length=N', Integer, "Number of samples to plot per channel (1-65536) [#{OPTS[:nsamps]}]") do |o|
    if (1025..65536) === o
      OPTS[:test] = true
    elsif ! ((1..1024) === o)
      STDERR.puts 'length option must be between 1 and 65536, inclusive'
      exit 1
    end
    OPTS[:nsamps] = o
  end
  op.on('-n', '--nxy=NX,NY', Array, "Controls subplot layout [auto]") do |o|
    if o.length != 2
      raise OptionParser::InvalidArgument.new('invalid NX,NY')
    end
    OPTS[:nxy] = o.map {|s| Integer(s) rescue 2}
  end
  op.on('-s', '--[no-]stats', "Include stats in plot titles [#{OPTS[:stats]}]") do |o|
    OPTS[:stats] = o
  end
  op.on('-t', '--type={time|freq|histo}', [:time, :freq, :histo], "Type of plot [#{OPTS[:type]}]") do |o|
    OPTS[:type] = o
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

if OPTS[:test]
  require 'adc16/test'
  adc16_class = ADC16Test
  snap_method = :snap_test
  device_check = 'snap_a_bram'
else
  adc16_class = ADC16
  snap_method = :snap
  device_check = 'adc16_controller'
end

# Define
if ! NArray.method_defined? :normal_pdf
  class NArray
    def normal_pdf(mean=0, var=1)
      1.0/Math.sqrt(var*2*Math::PI)*NMath.exp(-((self-mean)**2)/(2*var))
    end
  end
end

# Workaround Ruby/GSL limitation that half-complex
# form requires even number of data points.
if OPTS[:type] == :freq && OPTS[:nsamps] % 2 == 1
  OPTS[:nsamps] += 1
end

begin
  require 'gsl' unless OPTS[:type] == :time
rescue LoadError
  puts "error loading Ruby/GSL, reverting to time plot"
  OPTS[:type] = :time
end

a = adc16_class.new(ARGV[0])

# Verify suitability of current design
if !a.programmed?
  $stderr.puts 'FPGA not programmed'
  exit 1
elsif a.listdev.grep(device_check).empty?
  $stderr.puts "FPGA is not programmed with an appropriate #{adc16_class} design"
  exit 1
end

# Get number of channels per chip based on current demux mode
nchan_per_chip = case a.demux
                 when ADC16::DEMUX_BY_4; 1
                 when ADC16::DEMUX_BY_2; 2
                 else 4
                 end

# Chip chans will contain chip numbers for keys whose corresponding value is an
# Array of channels to plot for that chip.
chip_chans = {}
num_chans = 0
OPTS[:chans].each do |chan_name|
  chip, chan = ADC16.chip_chan(chan_name) rescue nil
  next unless chip
  next unless (1..nchan_per_chip) === chan
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
                         when 7,9; [3, 3]
                         when 8; [2, 4]
                         when 10..12; [4, 3]
                         else; [4, 4]
                         end
end

plot=Plotter.new(OPTS)
pgsch(2.0) if OPTS[:nx] * OPTS[:ny] > 2
pgsch(2.5) if OPTS[:nx] * OPTS[:ny] > 6

CHIP_NAMES = ('A'..'H').to_a

def plot_time(data, chip_num, chan)
  title2 = ''
  if OPTS[:stats]
    title2 = sprintf('min=%d mean=%.3f rms=%.3f max=%d',
      data.min, data.mean, data.rms, data.max)
  end

  plot(data,
       :line => :stairs,
       :title => "ADC Channel #{CHIP_NAMES[chip_num]}#{chan}",
       :title2 => title2,
       :ylabel => 'ADC Sample Value',
       :xlabel => 'Sample Number'
      )
end

def plot_freq(data, chip_num, chan, opts={
  :plot_max_line=>true,
  :plot_fs4_line=>true
})
  spec_amp = data.to_gv.forward!.hc_amp_phase[0].abs / Math.sqrt(data.length)

  title2 = ''
  if OPTS[:stats]
    fdata = spec_amp.to_na
    title2 = sprintf('max=%.3f @ bin %d of %d',
      fdata.max, fdata.eq(fdata.max).where[0], fdata.length)
  end

  # Zero-out DC channel for plot
  spec_amp[0] = 0

  plot(spec_amp,
       :line => :stairs,
       :title => "ADC Channel #{ADC16.chip_name(chip_num)}#{chan}",
       :title2 => title2,
       :ylabel => 'Amplitude',
       :xlabel => 'Frequency Channel'
      )

  # Plot a symbol at channel 0 to increase its visibility
  pgpt1(0, spec_amp[0], Marker::CIRCLE)

  pgsls(Line::DASHED)

  if OPTS[:plot_max_line]
    plot([0, OPTS[:nsamps]/2+1], [spec_amp.max]*2,
         :line_color => Color::WHITE,
         :overlay => true)
  end

  if OPTS[:plot_fs4_line]
    fs_4 = OPTS[:nsamps]/4
    # Plot marker at Fs/4 value to increase its visibility
    pgpt1(fs_4, spec_amp[fs_4], Marker::CIRCLE)
    plot([fs_4, fs_4], [0, spec_amp.max*2],
         :line_color => Color::WHITE,
         :overlay => true)
  end

  pgsls(Line::SOLID)
end

def plot_histo(data, chip_num, chan)
  histo = NArray.float(256)

  256.times do |i|
    histo[i] = data.eq(i-128).where.length
  end

  histo.div!(data.length)

  min_idx, max_idx = histo.where.to_a.minmax
  min, max = min_idx-128, max_idx-128

  # Ensure symmetry
  min = -max if -max < min
  max = -min if -min > max
  min_idx, max_idx = min+128, max+128
  max_idx = 255 if max_idx == 256

  xi = NArray.int(max-min+1).indgen!(min)
  xf = NArray.float((max-min)*20+21).indgen!(20*min).div!(20)
  yf = xf.normal_pdf(data.mean, data.rms**2)

  title2 = ''
  if OPTS[:stats]
    title2 = sprintf('min=%.3f mean=%.3f rms=%.3f max=%.3f',
      min, data.mean, data.rms, data.max)
  end

  plot(xi, histo[min_idx..max_idx],
       :line => :stairs,
       :title => "ADC Channel #{ADC16.chip_name(chip_num)}#{chan}",
       :title2 => title2,
       :ylabel => 'Occurrence',
       :xlabel => 'Sample Value',
       :xpad => 0.02
      )

  pgsls(Line::DOTTED)
  plot(xf, yf,
       :line_color => Color::DARK_GRAY,
       :overlay => true
      )
  pgsls(Line::SOLID)
end

chips = chip_chans.keys.sort
snap_args = chips
snap_args << {:n => OPTS[:nsamps]}
data = a.send(snap_method, *snap_args)
# Make sure data is an array of NArrays, even if only one element
data = [data].flatten
# Plot data
data.each_with_index do |chip_data, chips_idx|
  chip_num = chips[chips_idx]
  chip_chans[chip_num].each do |chan|
    case OPTS[:type]
    when :freq; plot_freq(chip_data[chan-1,nil], chip_num, chan)
    when :histo; plot_histo(chip_data[chan-1,nil], chip_num, chan)
    else plot_time(chip_data[chan-1,nil], chip_num, chan)
    end
  end
end

plot.close
