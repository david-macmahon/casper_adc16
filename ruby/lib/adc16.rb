require 'rubygems'
require 'katcp'
#require 'adc16/version'

class ADC16 < KATCP::RoachClient
  DEVICE_TYPEMAP = {
    :adc16_controller => :bram
  }

  def device_typemap
    DEVICE_TYPEMAP
  end

  def initialize(*args)
    super(*args)
    @chip_select = 0xff
  end

  def progdev(bof=@opts[:bof])
    super(bof)
  end

  # 8-bits of chip select values
  attr_accessor :chip_select
  alias :cs  :chip_select
  alias :cs= :chip_select=

  # Convert +chip_spec+ to zero-based chip number.  +chip_spec+ can be
  # a Symbol from :a to :h, an Integer from 0 to 7, or a string from 'a' to 'h'
  # or 'A' to 'H'.
  def self.chip_num(chip_spec)
    case chip_spec
    when 0, :a, 'a', 'A'; 0
    when 1, :b, 'b', 'B'; 1
    when 2, :c, 'c', 'C'; 2
    when 3, :d, 'd', 'D'; 3
    when 4, :e, 'e', 'E'; 4
    when 5, :f, 'f', 'F'; 5
    when 6, :g, 'g', 'G'; 6
    when 7, :h, 'h', 'H'; 7
    else
      raise "invalid chip spec '#{chip_spec}'"
    end
  end

  # ======================================= #
  # ADC16 3-Wire Register (word 0)          #
  # ======================================= #
  # LL = Clock locked bits                  #
  # NNNN = Number of ADC chips supported    #
  # RR = ROACH2 revision expected/required  #
  # C = SCLK                                #
  # D = SDATA                               #
  # 7 = CSNH (chip select H, active high)   #
  # 6 = CSNG (chip select G, active high)   #
  # 5 = CSNF (chip select F, active high)   #
  # 4 = CSNE (chip select E, active high)   #
  # 3 = CSND (chip select D, active high)   #
  # 2 = CSNC (chip select C, active high)   #
  # 1 = CSNB (chip select B, active high)   #
  # 0 = CSNA (chip select A, active high)   #
  # ======================================= #
  # |<-- MSb                       LSb -->| #
  # 0000_0000_0011_1111_1111_2222_2222_2233 #
  # 0123_4567_8901_2345_6789_0123_4567_8901 #
  # ---- --LL ---- ---- ---- ---- ---- ---- #
  # ---- ---- NNNN ---- ---- ---- ---- ---- #
  # ---- ---- ---- --RR ---- ---- ---- ---- #
  # ---- ---- ---- ---- ---- --C- ---- ---- #
  # ---- ---- ---- ---- ---- ---D ---- ---- #
  # ---- ---- ---- ---- ---- ---- 7654 3210 #
  # |<--- Status ---->| |<--- 3-Wire ---->| #
  # ======================================= #
  # NOTE: LL reflects the runtime lock      #
  #       status of a line clock from each  #
  #       ADC board.  A '1' bit means       #
  #       locked (good!).  Bit 5 is always  #
  #       used, but bit 6 is only used when #
  #       NNNN is 4 (or less).              #
  # ======================================= #
  # NOTE: NNNN and RR are read-only values  #
  #       that are set at compile time.     #
  #       They do not indicate the state    #
  #       of the actual hardware in use     #
  #       at runtime.                       #
  # ======================================= #

  SCL = 0x200
  SDA_SHIFT = 8
  IDLE_3WIRE = SCL

  def send_3wire_bit(bit)
    # Clock low, data and chip selects set accordingly
    adc16_controller[0] =       (chip_select&0xff) | ((bit&1) << SDA_SHIFT)
    # Clock high, data and chip selects set accordingly
    adc16_controller[0] = SCL | (chip_select&0xff) | ((bit&1) << SDA_SHIFT)
  end

  def setreg(addr, val)
    adc16_controller[0] = IDLE_3WIRE
    7.downto(0) {|i| send_3wire_bit(addr>>i)}
    15.downto(0) {|i| send_3wire_bit(val>>i)}
    adc16_controller[0] = IDLE_3WIRE
    self
  end

  LOCKED_SHIFT = 24
  LOCKED_MASK  =  3 # after left shift by LOCKED_SHIFT

  # Return the locked status of the ADC board(s).
  #
  #   0 = only no ADC clocks are locked (BAD)
  #   1 = only ADC0 clock is locked (OK if num_adcs <= 4, BAD if num_adcs >=5)
  #   2 = only ADC1 clock is locked (BAD since ADC0 clock is always needed)
  #   3 = both ADC clocks are locked (OK, but weird if num_adcs <=4)
  def locked_status
    (adc16_controller[0] >> LOCKED_SHIFT) & LOCKED_MASK
  end

  NUM_ADCS_SHIFT =  20
  NUM_ADCS_MASK  = 0xF # after left shift by NUM_ADCS_SHIFT

  # Returns the number of ADCS for which the gateware was built (currently
  # limited to 4 or 8).
  def num_adcs
    (adc16_controller[0] >> NUM_ADCS_SHIFT) & NUM_ADCS_MASK
  end

  ROACH2_REV_SHIFT = 16
  ROACH2_REV_MASK  =  3 # after left shift by ROACH2_REV_SHIFT

  def roach2_rev
    (adc16_controller[0] >> ROACH2_REV_SHIFT) & ROACH2_REV_MASK
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
    progdev @opts[:bof] if @opts[:bof]
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
  # ADC16 Control Register (word 1)         #
  # ======================================= #
  # R = ADC16 Reset                         #
  # S = Snap Request                        #
  # H = ISERDES Bit Slip Chip H             #
  # G = ISERDES Bit Slip Chip G             #
  # F = ISERDES Bit Slip Chip F             #
  # E = ISERDES Bit Slip Chip E             #
  # D = ISERDES Bit Slip Chip D             #
  # C = ISERDES Bit Slip Chip C             #
  # B = ISERDES Bit Slip Chip B             #
  # A = ISERDES Bit Slip Chip A             #
  # T = Delay Tap                           #
  # ======================================= #
  # |<-- MSb                       LSb -->| #
  # 0000 0000 0011 1111 1111 2222 2222 2233 #
  # 0123 4567 8901 2345 6789 0123 4567 8901 #
  # ---- ---- ---R ---- ---- ---- ---- ---- #
  # ---- ---- ---- ---S ---- ---- ---- ---- #
  # ---- ---- ---- ---- HGFE DCBA ---- ---- #
  # ---- ---- ---- ---- ---- ---- ---T TTTT #
  # ======================================= #

  SNAP_REQ = (1<<16)
  BITSLIP_SHIFT = 8
  DELAY_TAP_MASK = 0x1F

  def bitslip(*chips)
    val = 0
    chips.each do |c|
      val |= (1 << (BITSLIP_SHIFT+ADC16.chip_num(c)))
    end
    adc16_controller[1] = 0
    adc16_controller[1] = val
    adc16_controller[1] = 0

    self
  end

  # For each chip given in +chips+ (one or more of :a to :h, 0 to 7, 'a' to
  # 'h', or 'A' to 'H'), an NArray is returned.  By default, the NArray has
  # 4x1024 elements (i.e. the complete snapshot buffer), but a trailing Hash
  # argument can specify a shorter length to snap via the :n key.
  def snap(*chips)
    # A trailing Hash argument can be passed for options
    opts = (Hash === chips[-1]) ? chips.pop : {}
    len = opts[:n] || (1<<10)
    len =    1 if len <    1
    len = 1024 if len > 1024

    # Convert chips to integers
    chips.map! {|c| ADC16.chip_num(c)}

    adc16_controller[1] = 0
    adc16_controller[1] = SNAP_REQ
    adc16_controller[1] = 0

    out = chips.map do |chip|
      # Do snap
      d = adc16_controller[1024*chip+1024,len]
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

  # =============================================== #
  # ADC16 Delay A Strobe Register (word 2)          #
  # =============================================== #
  # D = Delay Strobe (rising edge active)           #
  # =============================================== #
  # |<-- MSb                              LSb -->|  #
  # 0000  0000  0011  1111  1111  2222  2222  2233  #
  # 0123  4567  8901  2345  6789  0123  4567  8901  #
  # DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  #
  # |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  #
  # H4 H1 G4 G1 F4 F1 E4 E1 D4 D1 C4 C1 B4 B1 A4 A1 #
  # =============================================== #

  # =============================================== #
  # ADC0 Delay B Strobe Register (word 3)           #
  # =============================================== #
  # D = Delay RST                                   #
  # =============================================== #
  # |<-- MSb                              LSb -->|  #
  # 0000  0000  0011  1111  1111  2222  2222  2233  #
  # 0123  4567  8901  2345  6789  0123  4567  8901  #
  # DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  #
  # |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  #
  # H4 H1 G4 G1 F4 F1 E4 E1 D4 D1 C4 C1 B4 B1 A4 A1 #
  # =============================================== #

  # Sets the delay tap for ADC +chip+ to +tap+ for channels specified in
  # +chans+ bitmask.  Bit 0 of +chans+ (i.e. 0x1, the least significant bit) is
  # channel 0, bit 1 (i.e. 0x2) is channel 1, etc.  A +chans+ value of 10
  # (0b1010) would set the delay taps for channels 1 and 3 of ADC +chip+.
  def delay_tap(chip, tap, chans=0b1111_1111)
    # Newer gateware versions (as of adc16_test_2013_Jan_19_0934) support
    # separate lane "a" and "b" delays.  In these newer versions, word 2 of
    # adc16_controller is the the strobe for the lane "a" delays and word 3 is
    # the strobe for the lane "b" delays.  For now, this routine sets the "a"
    # and "b" delays to be the same, just like the old gateware did.  Since
    # writing to word 3 has no effect on older gateware versions, this code can
    # still be used with older gateware.
    a_chans = (chans     ) & 0xf
    b_chans = (chans >> 4) & 0xf

    # Clear the strobe bits
    adc16_controller[2] = 0
    adc16_controller[3] = 0
    # Set tap bits
    adc16_controller[1] = tap & DELAY_TAP_MASK
    # Set the strobe bits
    adc16_controller[2] = a_chans << (4*ADC16.chip_num(chip))
    adc16_controller[3] = b_chans << (4*ADC16.chip_num(chip))
    # Clear all bits
    #adc16_controller[1,2] = [0, 0]
    adc16_controller[2] = 0
    adc16_controller[3] = 0
    adc16_controller[1] = 0

    self
  end

  def walk_taps(chip, opts={})
    # Allow caller to override default opts
    opts = {
      :expected => 0x2a,
      :num_iters => 1,
      :verbose => false
    }.merge!(opts)

    # Convert lowest 8 bits of opts[:expected] from unsigned byte to signed integer
    expected = opts[:expected] & 0xff
    expected -= 256 if expected >= 128

    # good_taps has four elements, one element for each channel;
    # each channel's element has two elements, one for each lane.
    good_taps = [[[],[]], [[],[]], [[],[]], [[],[]]]
    counts = [[], [], [], []]

    (0..31).each do |tap|
      delay_tap(chip, tap)
      chan_counts = [[0,0],[0,0],[0,0],[0,0]]
      opts[:num_iters].times do |iter|
        # Get snap data and convert to 8-by-N matrix of bytes
        d = snap(chip, :n=>1024).reshape(8,true)
        # Examine each channel in snap data and accumulate data
        4.times do |chan|
          even_errcount = d[chan  , nil].ne(expected).where.length # "even" samples
          odd_errcount  = d[chan+4, nil].ne(expected).where.length  # "odd"  samples
          chan_counts[chan][0] += even_errcount
          chan_counts[chan][1] += odd_errcount
          if opts[:verbose] == :very
            puts "chip #{chip} tap #{tap} chan #{chan} iter #{iter} err_counts [#{even_errcount}, #{odd_errcount}]"
          end
        end
      end

      # Check each channel's chan_counts
      4.times do |chan|
        counts[chan] << chan_counts[chan]
        good_taps[chan][0] << tap if chan_counts[chan][0] == 0
        good_taps[chan][1] << tap if chan_counts[chan][1] == 0
      end
    end

    # Set delay taps to middle of the good range
    set_taps = [[],[],[],[]]
    4.times do |chan|
      2.times do |lane|
        good_chan_taps = good_taps[chan][lane]
        next if good_chan_taps.empty? # uh-oh...
        # Handle case where good tap values wrap around from 31 to 0
        if good_chan_taps.max - good_chan_taps.min > 16
          low = good_chan_taps.find_all {|t| t < 16}
          hi  = good_chan_taps.find_all {|t| t > 15}
          low.map! {|t| t + 32}
          good_chan_taps = hi + low
        end
        best_chan_tap = good_chan_taps[good_chan_taps.length/2] % 32
        next if best_chan_tap.nil?  # TODO Warn or raise exception?
        delay_tap(chip, best_chan_tap, 1<<(chan+4*lane))
        puts "chip #{chip} chan #{chan} lane #{lane} setting tap=#{best_chan_tap}" if opts[:verbose]
        set_taps[chan][lane] = best_chan_tap
      end
    end

    [set_taps, counts]
  end

  def calibrate(opts={})
    # Allow caller to override default opts
    opts = {
      :chips => [:a, :b, :c, :d, :e, :f, :g, :h],
      :deskew_expected => 0x2a,
      :sync_expected => 0x70,
      :num_iters => 1,
      :verbose => false
    }.merge!(opts)

    # Make sure opts[:chips] is an Array (and allow :chip to override :chips)
    opts[:chips] = [opts[:chip]||opts[:chips]]
    opts[:chips].flatten!
    # Convert to chip numbers (and reject those that are not supported/used
    opts[:chips].map! {|c| c=ADC16.chip_num(c); c < num_adcs ? c : nil}
    opts[:chips].compact!
    puts "calibrating chips #{opts[:chips].inspect}" if opts[:verbose]

    # Create :expected alias for :deskew_expected so that opts can be passed to walk_taps
    opts[:expected] = opts[:deskew_expected] unless opts[:expected]

    # Error out if ADC0 is not locked
    raise 'ADC0 clock not locked' if (locked_status&1) == 0
    # Warn if ADC1 clock is not locked when num_adcs > 4
    warn 'warning: ADC1 clock not locked' if (locked_status&2) == 0 && num_adcs > 4

    # Set deskew pattern
    deskew_pattern
    opts[:chips].each {|chip| walk_taps(chip, opts)}
    # Set sync pattern
    sync_pattern
    # Convert lowest 8 bits of opts[:sync_expected] from unsigned byte to signed integer
    sync_expected = opts[:sync_expected] & 0xff
    sync_expected -= (1<<8) if sync_expected > (1<<7)

    # Bit slip each ADC
    status = opts[:chips].map do |chip|
      # Try up to 8 bitslip operations to get things right
      8.times do
        # Done if any (e.g. first) channel matches sync_expected
        break if snap(chip, :n=>1)[0] == sync_expected
        bitslip(chip)
      end
      # Verify sucessful sync-up
      snap(chip, :n=>1)[0] == sync_expected
    end
    status
  end

end # class ADC16
