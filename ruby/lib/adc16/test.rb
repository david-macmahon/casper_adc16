require 'adc16'

# Class for communicating with snap and trig blocks of adc16_test model.
class ADC16Test < ADC16

  DEFAULT_BOF = 'adc16_test_2012_Dec_20_1424.bof'

  def initialize(*args)
    super(*args)
    @opts[:bof] ||= DEFAULT_BOF
  end

  DEVICE_TYPEMAP = {
    :snap_a_bram   => :bram,
    :snap_b_bram   => :bram,
    :snap_c_bram   => :bram,
    :snap_d_bram   => :bram,
    :snap_a_status => :roreg,
    :snap_b_status => :roreg,
    :snap_c_status => :roreg,
    :snap_d_status => :roreg
  }

  def device_typemap
    super.merge!(DEVICE_TYPEMAP)
  end

  # For each chip given in +chips+ (one or more of :a to :d, 0 to 3, 'a' to
  # 'd', or 'A' to 'D'), an NArray is returned.  By default, the NArry has
  # 4x64K elements (i.e the complete snapshot buffer), but a trailing Hash
  # argument can specify the leth to snap via the :n key.
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
      # Reshape to 4-by-len matrix
      d.reshape!(4, true)
      # Convert to integers
      d = d.to_type(NArray::INT)
      # Convert to signed numbers
      d.add!(128).mod!(256).sbt!(128)
    end

    chips.length == 1 ? out[0] : out
  end

end # class ADC16Test
