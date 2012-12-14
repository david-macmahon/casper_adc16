require 'rubygems'
require 'katcp'

class ADC16 < KATCP::RoachClient
  DEVICE_TYPEMAP = {
    :adc16_controller => :bram,
    :snap_a_bram => :bram,
    :snap_b_bram => :bram,
    :snap_c_bram => :bram,
    :snap_d_bram => :bram
  }

  def device_typemap
    DEVICE_TYPEMAP
  end

  def initialize(*args)
    super(*args)
    @chip_select = 0b1111
  end

  # 4-bits of chip select values
  attr_accessor :chip_select
  alias :cs  :chip_select
  alias :cs= :chip_select=

  # ======================================= #
  # ADC0 3-Wire Register Bits               #
  # ======================================= #
  # C = SCLK (clock)                        #
  # D = SDATA (data)                        #
  # 0 = CSN1 (chip select 1)                #
  # 1 = CSN2 (chip select 2)                #
  # 2 = CSN3 (chip select 3)                #
  # 3 = CSN4 (chip select 4)                #
  # ======================================= #
  # |<-- MSb                       LSb -->| #
  # 0000_0000_0011_1111_1111_2222_2222_2233 #
  # 0123_4567_8901_2345_6789_0123_4567_8901 #
  # C--- ---- ---- ---- ---- ---- ---- ---- #
  # -D-- ---- ---- ---- ---- ---- ---- ---- #
  # --1- ---- ---- ---- ---- ---- ---- ---- #
  # ---2 ---- ---- ---- ---- ---- ---- ---- #
  # ---- 3--- ---- ---- ---- ---- ---- ---- #
  # ---- -4-- ---- ---- ---- ---- ---- ---- #
  # ======================================= #

  SCL = 1<<31
  SDA_SHIFT = 30
  CSN_SHIFT = 26
  IDLE_3WIRE = 0x3c00_0000

  def send_3wire_bit(bit)
    # Clock low, data and chip selects set accordingly
    adc16_controller[0] = ((  bit         &     1) << SDA_SHIFT) |
                          (((~chip_select)&0b1111) << CSN_SHIFT)
    # Clock high, data and chip selects set accordingly
    adc16_controller[0] = ((  bit         &     1) << SDA_SHIFT) |
                          (((~chip_select)&0b1111) << CSN_SHIFT) |
                          SCL
  end

  def setreg(addr, val)
    adc16_controller[0] = IDLE_3WIRE
    7.downto(0) {|i| send_3wire_bit(addr>>i)}
    15.downto(0) {|i| send_3wire_bit(val>>i)}
    adc16_controller[0] = IDLE_3WIRE
    self
  end

  def adc_reset
    setreg(0x00, 0x0001) # reset
  end

  def adc_power_cycle
    setreg(0x0f, 0x0200) # Powerdown
    setreg(0x0f, 0x0000) # Powerup
  end

  def adc_init
    raise 'FPGA not programmed' unless programmed?
    adc_reset
    adc_power_cycle
    progdev self.opts[:bof] if self.opts[:bof]
  end

  # Set output data endian-ness and binary format.  If +msb_invert+ is true,
  # then invert msb (i.e. output 2's complement (else straight offset binary).
  # If +msb_first+ is true, then output msb first (else lsb first).
  def data_format(invert_msb=false, msb_first=false)
    val = 0x0000
    val |= invert_msb ? 4 : 0
    val |= msb_first ? 8 : 0
    setreg(0x46, val)
  end

  # +ptn+ can be any of:
  #
  #   :ramp            Ramp pattern 0-255
  #   :deskew (:eye)   Deskew pattern (01010101)
  #   :sync (:frame)   Sync pattern (11110000)
  #   :custom1         Custom1 pattern
  #   :custom2         Custom2 pattern
  #   :dual            Dual custom pattern
  #   :none            No pattern
  #
  # Default is :ramp.  Any value other than shown above is the same as :none.
  def enable_pattern(ptn=:ramp)
    setreg(0x25, 0x0000)
    setreg(0x45, 0x0000)
    case ptn
    when :ramp;           setreg(0x25, 0x0040)
    when :deskew, :eye;   setreg(0x45, 0x0001)
    when :sync, :frame;   setreg(0x45, 0x0002)
    when :custom;         setreg(0x25, 0x0010)
    when :dual;           setreg(0x25, 0x0020)
    end
  end

  def clear_pattern;  enable_pattern :none;   end
  def ramp_pattern;   enable_pattern :ramp;   end
  def deskew_pattern; enable_pattern :deskew; end
  def sync_pattern;   enable_pattern :sync;   end
  def custom_pattern; enable_pattern :custom; end
  def dual_pattern;   enable_pattern :dual;   end
  def no_pattern;     enable_pattern :none;   end

  # Set the custom bits 1 from the lowest 8 bits of +bits+.
  def custom1=(bits)
    setreg(0x26, (bits&0xff) << 8)
  end

  # Set the custom bits 2 from the lowest 8 bits of +bits+.
  def custom2=(bits)
    setreg(0x27, (bits&0xff) << 8)
  end

  # ======================================= #
  # ADC0 Control Register Bits              #
  # ======================================= #
  # D = Delay RST                           #
  # T = Delay Tap                           #
  # B = ISERDES Bit Slip                    #
  # P = Load Phase Set                      #
  # R = Reset                               #
  # ======================================= #
  # |<-- MSb                       LSb -->| #
  # 0000 0000 0011 1111 1111 2222 2222 2233 #
  # 0123 4567 8901 2345 6789 0123 4567 8901 #
  # DDDD DDDD DDDD DDDD ---- ---- ---- ---- #
  # ---- ---- ---- ---- TTTT T--- ---- ---- #
  # ---- ---- ---- ---- ---- -BBB B--- ---- #
  # ---- ---- ---- ---- ---- ---- -PPP P--- #
  # ---- ---- ---- ---- ---- ---- ---- -R-- #
  # ======================================= #

  TAP_SHIFT = 11
  ADC_A_BITSLIP = 0x080
  ADC_B_BITSLIP = 0x100
  ADC_C_BITSLIP = 0x200
  ADC_D_BITSLIP = 0x400
  ADC_A_PHASE = 0x08
  ADC_B_PHASE = 0x10
  ADC_C_PHASE = 0x20
  ADC_D_PHASE = 0x40
  PHASE_MASK  =  ADC_A_PHASE | ADC_B_PHASE | ADC_C_PHASE |ADC_D_PHASE

  def bitslip(*chips)
    # Preserve "load phase set" bits
    val = adc16_controller[1] & PHASE_MASK
    chips.each do |c|
      val |= case c
            when 0, :a, 'a', 'A'; ADC_A_BITSLIP
            when 1, :b, 'b', 'B'; ADC_B_BITSLIP
            when 2, :c, 'c', 'C'; ADC_C_BITSLIP
            when 3, :d, 'd', 'D'; ADC_D_BITSLIP
            end
    end
    adc16_controller[1] = 0
    adc16_controller[1] = val
    adc16_controller[1] = 0
    self
  end

  def toggle_phase(chip)
    # Clear all but "load phase set" bits
    val = adc16_controller[1] & PHASE_MASK
    adc16_controller[1] = val
    # Toggle chip specific phase bits
    case chip
    when 0, :a, 'a', 'A'; val ^= ADC_A_PHASE
    when 1, :b, 'b', 'B'; val ^= ADC_B_PHASE
    when 2, :c, 'c', 'C'; val ^= ADC_C_PHASE
    when 3, :d, 'd', 'D'; val ^= ADC_D_PHASE
    else raise "Invalid chip: #{chip}"
    end
    # Write new value
    adc16_controller[1] = val
    self
  end

  # Sets the delay tap for ADC +chip+ to +tap+ for channels specified in
  # +chans+ bitmask.  Bit 0 of +chans+ (i.e. 0x1, the least significant bit) is
  # channel 0, bit 1 (i.e. 0x2) is channel 1, etc.  A +chans+ value of 10
  # (0b1010) would set the delay taps for channels 1 and 3 of ADC +chip+.
  def delay_tap(chip, tap, chans=0b1111)
    # Current gateware treats +chans+ in a bit-reversed way relative to the
    # above documentation, so for now the code bit-reveres the lower four bits.
    chans = ((chans&1)<<3) | ((chans&2)<<1) | ((chans&4)>>1) | ((chans&8)>>3)
    # Clear all but "load phase set" bits
    val = adc16_controller[1] & PHASE_MASK
    adc16_controller[1] = val
    # Set tap bits
    val |= (tap&0x1f) << TAP_SHIFT
    # Write value with reset bits off
    # (avoids unconstrained path race condition)
    adc16_controller[1] = val
    # Set chip specific reset bits for the requested channels
    case chip
    when 0, :a, 'a', 'A'; val |= (chans&0xf) << 16
    when 1, :b, 'b', 'B'; val |= (chans&0xf) << 20
    when 2, :c, 'c', 'C'; val |= (chans&0xf) << 24
    when 3, :d, 'd', 'D'; val |= (chans&0xf) << 28
    else raise "Invalid chip: #{chip}"
    end
    # Write value with reset bits on
    adc16_controller[1] = val
    # Clear all but "load phase set" bits
    adc16_controller[1] = val & PHASE_MASK
    sleep 0.1
    self
  end

end # class ADC16

# Class for communicating with snap and trig blocks of adc16_test model.
class ADC16Test < ADC16

  # For each chip given in +chips+ (one or more of :a to :d, 0 to 3, 'a' to
  # 'd', or 'A' to 'D'), a 64K NArray is returned.  A trailing Hash argument
  # can specify the leth to snap via the :n key.
  def snap(*chips)
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
      # snap_x_ctrl bit 3: cirular capture (0=one-shot, 1=circular)
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
      send("snap_#{chip}_bram")[0,len]
    end
    chips.length == 1 ? out[0] : out
  end

  def walk_taps(chip, expected=0x2a)
    good_taps = [[], [], [], []]
    counts = [[], [], [], []]
    (0..31).each do |tap|
      delay_tap(chip, tap)
      # Get snap data and convert to matrix of bytes
      d = snap(chip).hton.to_type_as_binary(NArray::BYTE).reshape(8,true)
      4.times do |chan|
        chan_counts = [
          d[chan  , nil].ne(expected).where.length, # "even" samples
          d[chan+4, nil].ne(expected).where.length  # "odd"  samples
        ]
        counts[chan] << chan_counts
        good_taps[chan] << tap if chan_counts == [0,0] # Good when both even and odd errors are 0
      end
    end

    # Set delay taps to middle of the good range
    4.times do |chan|
      good_chan_taps = good_taps[chan]
      best_chan_tap = good_chan_taps[good_chan_taps.length/2]
      next if best_chan_tap.nil?  # TODO Warn or raise exception?
      delay_tap(chip, best_chan_tap, 1<<chan)
    end

    [good_taps, counts]
  end

  def plot_all(opts={})
    opts = {
      :expected => 0x2a,
      :device => '/xs',
      :nx => 4,
      :ny => 4
    }.merge!(opts)
    plot=Plotter.new(opts)
    ['A', 'B', 'C', 'D'].each do |chip|
      good, counts = walk_taps(chip, opts[:expected])
      4.times do |chan|
        title2 = "ADC #{chip} chan #{chan}"
        plot_counts(counts[chan], :title2 => title2)
      end
    end
    plot.close
    self
  end # plot_all

end # class ADC16Test

def plot_counts(counts, plotopts={})
  plotopts = {
    :line => :none,
    :marker => Marker::STAR,
    :title => 'Error Counts vs Delay Tap',
    :ylabel => 'log2(err_count+1)',
    :xlabel => 'Delay Tap Value'
  }.merge!(plotopts)
  logcounts=log2(NArray[*counts].to_f+1)
  plotopts[:overlay] = false
  plot(logcounts[0,nil], plotopts)
  plotopts[:overlay] = true
  plot(logcounts[1,nil], plotopts)
end
