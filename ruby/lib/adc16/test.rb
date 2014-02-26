require 'adc16'

# Class for communicating with snap and trig blocks of adc16_test model.
class ADC16Test < ADC16

  DEFAULT_BOF = 'adc16_test_rev2x8.bof'

  # Class for manipulating histogram devices of adc16_test design
  class Histo < KATCP::Bram
    def initialize(katcp_client, device_name)
      super
      @device_stem = device_name.sub(/_[04]$/, '')
    end

    def clear
      @zeros_1k ||= NArray.int(1024)
      @katcp_client.write("#{@device_stem}_0", 0, @zeros_1k)
      @katcp_client.write("#{@device_stem}_4", 0, @zeros_1k)
    end

    # Returns a 256x8 NArray.  histo[nil,i] is a 256 element histogram of every
    # eighth sample (0..7 === i).  histo.sum(1) is a 256 element histogram of
    # every sample.
    def histo
      d0 = @katcp_client.read("#{@device_stem}_0", 0, 1024).reshape(256,4)
      d4 = @katcp_client.read("#{@device_stem}_4", 0, 1024).reshape(256,4)
      # Create 256x8 NArray of floats and store two halves in it
      nn = NArray.float(256,8)
      nn[nil, 0..3] = d0.to_type(NArray::FLOAT)
      nn[nil, 4..7] = d4.to_type(NArray::FLOAT)
      # Convert negative values to unwrapped positive values
      # (-1 -> 2**32-1)
      nn.add!(2**32).mod!(2**32)
      nn
    end

    # Returns the mean calculated from histogram data in NArray +nn+.  The
    # first dimenstion of +nn+ (i.e. <code>nn.shape[0]</code> is the number of
    # bins.  The X value for each bin goes from <code>-floor(nbins/2)</code> to
    # <code>nbins+floor(nbins/2)-1</code>.
    #
    # If +demux+ is true, an NAray of means is returned, one per histogram in
    # +nn+ (e.g. if +nn+ is two dimensional such as the return value from
    # #histo.  If +demux+ is false (the default), the mean of all histograms is
    # returned.
    #
    # To get the overall mean for all eight "sub-histograms" such as returned
    # by #histo, pass <code>false</code> (or nothing) for +demux+.  To get the
    # means for each of the eight "sub-histograms", pass <code>true</code> for
    # +demux+.
    def self.mean(nn, demux=false)
      dim = demux ? [0] : []
      nbins = nn.shape[0]
      xx = NArray.float(*nn.shape).indgen!.mod!(nbins).sbt!(nbins/2)
      (nn*xx).sum(*dim).to_f/nn.sum(*dim)
    end

    # Reads the histogram data and returns the mean calculated from it.  If no
    # samples have been accumulated (i.e. all bins contain 0), then NaN
    # is returned.
    #
    # If +demux+ is true, an NAray of means is returned, one per
    # "sub-histogram".  If demux is false (the default), the mean of all
    # histograms is returned.
    #
    # To get the overall mean for all eight "sub-histograms" such as returned
    # by #histo, pass <code>false</code> (the default) for +demux+.  To get the
    # means for each of the eight "sub-histograms", pass <code>true</code> for
    # +demux+.
    def mean(demux=false)
      self.class.mean(histo, demux)
    end

    # Returns the standard deviation calculated from histogram data in NArray
    # +nn+.  The first dimenstion of +nn+ (i.e. <code>nn.shape[0]</code> is the
    # number of bins.  The X value for each bin goes from
    # <code>-floor(nbins/2)</code> to <code>nbins+floor(nbins/2)-1</code>.
    #
    # If +demux+ is true, an NAray of standard deviations is returned, one per
    # histogram in +nn+ (e.g. if +nn+ is two dimensional such as the return
    # value from #histo.  If +demux+ is false (the default), the standard
    # deviation of all histograms is returned.
    #
    # To get the overall standard deviation for all eight "sub-histograms" such
    # as returned by #histo, pass nothing for +demux+.  To get the standard
    # deviations for each of the eight "sub-histograms", pass <code>0</code>
    # for +demux+.
    def self.stddev(nn, demux=false)
      m = mean(nn, demux)
      # Convert non-NArray (e.g Float) mean to Array
      m = [m] unless NArray === m
      # Create xx NArray
      nbins = nn.shape[0]
      xx = NArray.float(nbins).indgen!.mod!(nbins).sbt!(nbins/2)
      # Create sd NArray
      sd = NArray.float(m.length)
      sd.length.times do |i|
        p = nn[nil,i] / nn[nil,i].sum
        variance = (p * (xx-m[i])**2).sum
        sd[i] = sqrt(variance)
      end
      (sd.length == 1) ? sd[0] : sd
    end

    class <<self
      alias sd  stddev
      alias std stddev
    end

    # Reads the histogram data and returns the mean calculated from it.  If no
    # samples have been accumulated (i.e. all bins contain 0), then NaN
    # is returned.
    #
    # If +demux+ is true, an NAray of standard deviations is returned, one per
    # "sub-histogram".  If +demux+ is false (the default), the overall standard
    # deviation is returned.
    #
    # To get the overall standard deviation for all eight "sub-histograms" such
    # as returned by #histo, pass <code>false</code> (the default) for +demux+.
    # To get the standard deviations for each of the eight "sub-histograms",
    # pass <code>true</code> for +demux+.
    def stddev(demux=false)
      self.class.std(histo, demux)
    end

    alias sd  stddev
    alias std stddev
  end

  # Sets a default BOF file to DEFAULT_BOF if none passed in by caller.
  def initialize(*args)
    super(*args)
    @opts[:bof] ||= DEFAULT_BOF
  end

  # Map device names to device types.  OK to list devices that may not be
  # present.
  DEVICE_TYPEMAP = superclass::DEVICE_TYPEMAP.merge({
    :histo_a1_0    => [Histo, :histo_a1],
    :histo_a1_4    => :skip,
    :histo_a2_0    => [Histo, :histo_a2],
    :histo_a2_4    => :skip,
    :histo_a3_0    => [Histo, :histo_a3],
    :histo_a3_4    => :skip,
    :histo_a4_0    => [Histo, :histo_a4],
    :histo_a4_4    => :skip,
    :histo_b1_0    => [Histo, :histo_b1],
    :histo_b1_4    => :skip,
    :histo_b2_0    => [Histo, :histo_b2],
    :histo_b2_4    => :skip,
    :histo_b3_0    => [Histo, :histo_b3],
    :histo_b3_4    => :skip,
    :histo_b4_0    => [Histo, :histo_b4],
    :histo_b4_4    => :skip,
    :histo_c1_0    => [Histo, :histo_c1],
    :histo_c1_4    => :skip,
    :histo_c2_0    => [Histo, :histo_c2],
    :histo_c2_4    => :skip,
    :histo_c3_0    => [Histo, :histo_c3],
    :histo_c3_4    => :skip,
    :histo_c4_0    => [Histo, :histo_c4],
    :histo_c4_4    => :skip,
    :histo_d1_0    => [Histo, :histo_d1],
    :histo_d1_4    => :skip,
    :histo_d2_0    => [Histo, :histo_d2],
    :histo_d2_4    => :skip,
    :histo_d3_0    => [Histo, :histo_d3],
    :histo_d3_4    => :skip,
    :histo_d4_0    => [Histo, :histo_d4],
    :histo_d4_4    => :skip,
    :histo_e1_0    => [Histo, :histo_e1],
    :histo_e1_4    => :skip,
    :histo_e2_0    => [Histo, :histo_e2],
    :histo_e2_4    => :skip,
    :histo_e3_0    => [Histo, :histo_e3],
    :histo_e3_4    => :skip,
    :histo_e4_0    => [Histo, :histo_e4],
    :histo_e4_4    => :skip,
    :histo_f1_0    => [Histo, :histo_f1],
    :histo_f1_4    => :skip,
    :histo_f2_0    => [Histo, :histo_f2],
    :histo_f2_4    => :skip,
    :histo_f3_0    => [Histo, :histo_f3],
    :histo_f3_4    => :skip,
    :histo_f4_0    => [Histo, :histo_f4],
    :histo_f4_4    => :skip,
    :histo_g1_0    => [Histo, :histo_g1],
    :histo_g1_4    => :skip,
    :histo_g2_0    => [Histo, :histo_g2],
    :histo_g2_4    => :skip,
    :histo_g3_0    => [Histo, :histo_g3],
    :histo_g3_4    => :skip,
    :histo_g4_0    => [Histo, :histo_g4],
    :histo_g4_4    => :skip,
    :histo_h1_0    => [Histo, :histo_h1],
    :histo_h1_4    => :skip,
    :histo_h2_0    => [Histo, :histo_h2],
    :histo_h2_4    => :skip,
    :histo_h3_0    => [Histo, :histo_h3],
    :histo_h3_4    => :skip,
    :histo_h4_0    => [Histo, :histo_h4],
    :histo_h4_4    => :skip,
    :histo_en      => :rwreg,
    :snap_a_bram   => :bram,
    :snap_b_bram   => :bram,
    :snap_c_bram   => :bram,
    :snap_d_bram   => :bram,
    :snap_e_bram   => :bram,
    :snap_f_bram   => :bram,
    :snap_g_bram   => :bram,
    :snap_h_bram   => :bram,
    :snap_a_status => :roreg,
    :snap_b_status => :roreg,
    :snap_c_status => :roreg,
    :snap_d_status => :roreg,
    :snap_e_status => :roreg,
    :snap_f_status => :roreg,
    :snap_g_status => :roreg,
    :snap_h_status => :roreg,
    :sync_count    => :roreg,
    :sync_period   => :roreg
  }) # :nodoc:

  def device_typemap # :nodoc:
    @device_typemap ||= DEVICE_TYPEMAP.dup
  end

  # For each chip given in +chips+ (one or more of :a to :h, 0 to 7, 'a' to
  # 'h', or 'A' to 'H'), an NArray is returned.  By default, each NArry has
  # 4x64K elements (i.e the complete snapshot buffer), but a trailing Hash
  # argument can specify the length to snap via the :n key.
  #
  # This is a larger snapshot than the built-in snapshot blocks (accessible via
  # ADC16#snap), but there is no a/b lane to even/odd sample consistency in
  # this larger snapshot block.
  def snap_test(*chips)
    # A trailing Hash argument can be passed for options
    opts = (Hash === chips[-1]) ? chips.pop : {}
    len = opts[:n] || (1<<16)

    # Convert chips to symbols
    chips.map! do |chip|
      case chip
      when 0, :a, 'a', 'A'; :a
      when 1, :b, 'b', 'B'; :b
      when 2, :c, 'c', 'C'; :c
      when 3, :d, 'd', 'D'; :d
      when 4, :e, 'e', 'E'; :e
      when 5, :f, 'f', 'F'; :f
      when 6, :g, 'g', 'G'; :g
      when 7, :h, 'h', 'H'; :h
      else raise "Invalid chip: #{chip}"
      end
    end

    self.trig = 0
    chips.each do |chip|
      # snap_x_ctrl bit 0: 0-to-1 = enable
      # snap_x_ctrl bit 1: trigger (0=external, 1=immediate)
      # snap_x_ctrl bit 2: write enable (0=external, 1=always)
      # snap_x_ctrl bit 3: circular capture (0=one-shot, 1=circular)
      #
      # Due to tcpborphserver3 bug, writes to the control registers must be
      # done using the KATCP ?wordwrite command.  See the email thread at
      # http://www.mail-archive.com/casper@lists.berkeley.edu/msg03457.html
      request(:wordwrite, "snap_#{chip}_ctrl", 0, 0b0000);
      request(:wordwrite, "snap_#{chip}_ctrl", 0, 0b0101);
    end
    self.trig = 1
    sleep 0.01
    self.trig = 0
    chips.each do |chip|
      request(:wordwrite, "snap_#{chip}_ctrl", 0, 0b0000);
    end
    out = chips.map do |chip|
      # Do snap
      d = send("snap_#{chip}_bram")[0,len]
      # Convert to NArray if len == 1
      if len == 1
        d -= (1<<32) if d >= (1<<31)
        d=NArray[d]
      end
      # Convert to bytes
      d = d.hton.to_type_as_binary(NArray::BYTE)
      case demux
      when DEMUX_BY_1
        # Reshape to 4-by-1*len matrix
        d.reshape!(4, true)
      when DEMUX_BY_2
        # Reshape to 2-by-2*len matrix
        d.reshape!(4, true)
        d2 = NArray.byte(2, 2*len)
        d2[0, nil] = d[0..1, nil].reshape(2*len)
        d2[1, nil] = d[2..3, nil].reshape(2*len)
        d = d2
      when DEMUX_BY_4
        # Reshape to 1-by-4*len matrix
        d.reshape!(1, true)
      end
      # Convert to integers
      d = d.to_type(NArray::INT)
      # Convert to signed numbers
      d.add!(128).mod!(256).sbt!(128)
    end

    chips.length == 1 ? out[0] : out
  end # #snap_test

  # Reads the histograms from the histogram devices of adc16_test design as
  # specified by +chips+.  For each chip given in +chips+ (one or more of :a to
  # :h, 0 to 7, 'a' to 'h', or 'A' to 'H'), an NArray is returned.  The
  # dimensions of the returned NArray depend on the demux factor.
  #
  # If the demux factor is 1, then each returned NArray is 256x4 (one 256
  # element histogram for each of the four distinct inputs per chip).
  #
  # If the demux factor is 2, then each returned NArray is 256x2 (one 256
  # element histogram for each of the two distinct inputs per chip).
  #
  # If the demux factor is 4, then each returned NArray is 256 long (one 256
  # element histogram for the single input per chip).
  #
  # The elements of each 256 element histogram are the counts of ADC samples
  # ranging from -128 (index 0) to +127 (index 255).
  def histo(*chips)
    demux_mode = demux # Cache demux mode in local variable

    histos = chips.map do |c|
      chip_name = ADC16.chip_name(c).downcase
      h1 = self.send("histo_#{chip_name}1").histo.sum(1)
      h2 = self.send("histo_#{chip_name}2").histo.sum(1)
      h3 = self.send("histo_#{chip_name}3").histo.sum(1)
      h4 = self.send("histo_#{chip_name}4").histo.sum(1)
      h = nil
      case demux_mode
      when DEMUX_BY_1
        h = NArray.int(256,4)
        h[nil,0] = h1
        h[nil,1] = h2
        h[nil,2] = h3
        h[nil,3] = h4
      when DEMUX_BY_2
        h = NArray.int(256,2)
        h[nil,0] = h1
        h[nil,0].add!(h2)
        h[nil,1] = h3
        h[nil,1].add!(h4)
      when DEMUX_BY_4
        h = h1
        h.add!(h2)
        h.add!(h3)
        h.add!(h4)
      end
      h
    end
    histos = histos[0] if histos.length == 1
    histos
  end # #histo

  # Clears the histogram devices of the specified chip.
  def clear_histo(*chips)
    chips.each do |c|
      chip_name = ADC16.chip_name(c).downcase
      (1..4).each do |chan|
        self.send("histo_#{chip_name}#{chan}").clear
      end
    end
    self
  end # #clear_histo

  # Enables the the histogram devices for approximately +secs+ seconds, which
  # can be a floating point number.
  def run_histo(secs=1.0)
    self.histo_en = 1
    sleep secs
    self.histo_en = 0
    self
  end # #run_histo

end # class ADC16Test
