require 'rubygems'

# We need a katcp version in which RoachClient defines DEVICE_TYPEMAP.
# That was introduced in katcp 0.1.10.
gem 'katcp', '~> 0.1.10'
require 'katcp'

# Provides KATCP wrapper around ADC16 based CASPER design.  Includes many
# convenience functions for writing to the registers of the ADC chips,
# calibrating the SERDES blocks, and accessing status info about the ADC16
# design and clock status.  While most access will be done via the methods of
# this class, there may be occasion to access the ADC16 controller directly
# (via the #adc16_controller method, which returns a KATCP::Bram object).
#
# Here is the memory map for the underlying #adc16_controller device:
#
#   # ======================================= #
#   # ADC16 3-Wire Register (word 0)          #
#   # ======================================= #
#   # LL = Clock locked bits                  #
#   # NNNN = Number of ADC chips supported    #
#   # RR = ROACH2 revision expected/required  #
#   # C = SCLK                                #
#   # D = SDATA                               #
#   # 7 = CSNH (chip select H, active high)   #
#   # 6 = CSNG (chip select G, active high)   #
#   # 5 = CSNF (chip select F, active high)   #
#   # 4 = CSNE (chip select E, active high)   #
#   # 3 = CSND (chip select D, active high)   #
#   # 2 = CSNC (chip select C, active high)   #
#   # 1 = CSNB (chip select B, active high)   #
#   # 0 = CSNA (chip select A, active high)   #
#   # ======================================= #
#   # |<-- MSb                       LSb -->| #
#   # 0000_0000_0011_1111_1111_2222_2222_2233 #
#   # 0123_4567_8901_2345_6789_0123_4567_8901 #
#   # ---- --LL ---- ---- ---- ---- ---- ---- #
#   # ---- ---- NNNN ---- ---- ---- ---- ---- #
#   # ---- ---- ---- --RR ---- ---- ---- ---- #
#   # ---- ---- ---- ---- ---- --C- ---- ---- #
#   # ---- ---- ---- ---- ---- ---D ---- ---- #
#   # ---- ---- ---- ---- ---- ---- 7654 3210 #
#   # |<--- Status ---->| |<--- 3-Wire ---->| #
#   # ======================================= #
#   # NOTE: LL reflects the runtime lock      #
#   #       status of a line clock from each  #
#   #       ADC board.  A '1' bit means       #
#   #       locked (good!).  Bit 5 is always  #
#   #       used, but bit 6 is only used when #
#   #       NNNN is 4 (or less).              #
#   # ======================================= #
#   # NOTE: NNNN and RR are read-only values  #
#   #       that are set at compile time.     #
#   #       They do not indicate the state    #
#   #       of the actual hardware in use     #
#   #       at runtime.                       #
#   # ======================================= #
#
#   # ======================================= #
#   # ADC16 Control Register (word 1)         #
#   # ======================================= #
#   # W  = Deux write-enable                  #
#   # MM = Demux mode                         #
#   # R = ADC16 Reset                         #
#   # S = Snap Request                        #
#   # H = ISERDES Bit Slip Chip H             #
#   # G = ISERDES Bit Slip Chip G             #
#   # F = ISERDES Bit Slip Chip F             #
#   # E = ISERDES Bit Slip Chip E             #
#   # D = ISERDES Bit Slip Chip D             #
#   # C = ISERDES Bit Slip Chip C             #
#   # B = ISERDES Bit Slip Chip B             #
#   # A = ISERDES Bit Slip Chip A             #
#   # T = Delay Tap                           #
#   # ======================================= #
#   # |<-- MSb                       LSb -->| #
#   # 0000 0000 0011 1111 1111 2222 2222 2233 #
#   # 0123 4567 8901 2345 6789 0123 4567 8901 #
#   # ---- -WMM ---- ---- ---- ---- ---- ---- #
#   # ---- ---- ---R ---- ---- ---- ---- ---- #
#   # ---- ---- ---- ---S ---- ---- ---- ---- #
#   # ---- ---- ---- ---- HGFE DCBA ---- ---- #
#   # ---- ---- ---- ---- ---- ---- ---T TTTT #
#   # ======================================= #
#   # NOTE: W enables writing the MM bits.    #
#   #       Some of the other bits in this    #
#   #       register are one-hot.  Using      #
#   #       W ensures that the MM bits will   #
#   #       only be written to when desired.  #
#   #       00: demux by 1 (single channel)   #
#   # ======================================= #
#   # NOTE: MM selects the demux mode.        #
#   #       00: demux by 1 (single channel)   #
#   #       01: demux by 2 (dual channel)     #
#   #       10: demux by 4 (quad channel)     #
#   #       11: undefined                     #
#   #       ADC board.  A '1' bit means       #
#   #       locked (good!).  Bit 5 is always  #
#   #       used, but bit 6 is only used when #
#   #       NNNN is 4 (or less).              #
#   # ======================================= #
#
#   # =============================================== #
#   # ADC16 Delay A Strobe Register (word 2)          #
#   # =============================================== #
#   # D = Delay Strobe (rising edge active)           #
#   # =============================================== #
#   # |<-- MSb                              LSb -->|  #
#   # 0000  0000  0011  1111  1111  2222  2222  2233  #
#   # 0123  4567  8901  2345  6789  0123  4567  8901  #
#   # DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  #
#   # |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  #
#   # H4 H1 G4 G1 F4 F1 E4 E1 D4 D1 C4 C1 B4 B1 A4 A1 #
#   # =============================================== #
#
#   # =============================================== #
#   # ADC0 Delay B Strobe Register (word 3)           #
#   # =============================================== #
#   # D = Delay Strobe (rising edge active)           #
#   # =============================================== #
#   # |<-- MSb                              LSb -->|  #
#   # 0000  0000  0011  1111  1111  2222  2222  2233  #
#   # 0123  4567  8901  2345  6789  0123  4567  8901  #
#   # DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  DDDD  #
#   # |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  #
#   # H4 H1 G4 G1 F4 F1 E4 E1 D4 D1 C4 C1 B4 B1 A4 A1 #
#   # =============================================== #

class ADC16 < KATCP::RoachClient
  DEVICE_TYPEMAP = superclass::DEVICE_TYPEMAP.merge({
    :adc16_controller => :bram
  }) # :nodoc:

  def device_typemap # :nodoc:
    @device_typemap ||= DEVICE_TYPEMAP.dup
  end

  # Standard KATCP::RoachClient arguments, plus support for:
  #   :bof => BOF_FILE
  def initialize(*args)
    super(*args)
    @chip_select = 0xff
  end

  # Programs FPGA.  If bof is not given, any BOF file passed to "#new" will be
  # used.  Passing +nil+ will deprogram the FPGA.
  def progdev(bof=@opts[:bof])
    super(bof)
  end

  # Eight bits of chip select values.  Bit 0 (the least significant bit)
  # selects ADC A; bit 7 selects ADC H.  A value of '1' selects the ADC; '0'
  # deselects it.
  attr_accessor :chip_select
  alias :cs  :chip_select
  alias :cs= :chip_select=

  # Convert +chip_spec+ to zero-based chip number.  +chip_spec+ can be
  # a Symbol from :a to :h, an Integer from 0 to 7, or a string from 'a' to 'h'
  # or 'A' to 'H'.
  def self.chip_num(chip_spec)
    case chip_spec
    when 0, '0', :a, 'a', 'A'; 0
    when 1, '1', :b, 'b', 'B'; 1
    when 2, '2', :c, 'c', 'C'; 2
    when 3, '3', :d, 'd', 'D'; 3
    when 4, '4', :e, 'e', 'E'; 4
    when 5, '5', :f, 'f', 'F'; 5
    when 6, '6', :g, 'g', 'G'; 6
    when 7, '7', :h, 'h', 'H'; 7
    else
      raise "invalid chip spec #{chip_spec.inspect}"
    end
  end

  # Returns name of chip given by +chip_spec+.  See #chip_num for allowable
  # +chip_spec+ values.
  def self.chip_name(chip_spec)
    (?A.ord + chip_num(chip_spec)).chr
  end

  # Returns chip name and channel number for +chan_name+, which must be a two
  # character String or Symbol whose first character is in the range A-H (or
  # a-h) and whose second character is in the range 1-4.  For example, "A1"
  # specifies channel 1 of ADC A.  An exception is raised if +chan_name+ is
  # malformed.
  #
  # Example:
  #
  #   >> ADC16.chip_chan(:b4)
  #   => ["b", 4]
  def self.chip_chan(chan_name)
    matchdata = /^([A-Ha-h])([1-4])$/.match(chan_name)
    raise 'channel name must be X#, where X is A-H and # is 1-4' unless matchdata
    chip, chan = matchdata.captures
    [chip, chan.to_i]
  end

  SCL = 0x200      # :nodoc:
  SDA_SHIFT = 8    # :nodoc:
  IDLE_3WIRE = SCL # :nodoc:

  def send_3wire_bit(bit) # :nodoc:
    # Clock low, data and chip selects set accordingly
    adc16_controller[0] =       (chip_select&0xff) | ((bit&1) << SDA_SHIFT)
    # Clock high, data and chip selects set accordingly
    adc16_controller[0] = SCL | (chip_select&0xff) | ((bit&1) << SDA_SHIFT)
  end

  # Sets register +addr+ to +val+ on all chips selected by +chip_select+.
  def setreg(addr, val)
    adc16_controller[0] = IDLE_3WIRE
    7.downto(0) {|i| send_3wire_bit(addr>>i)}
    15.downto(0) {|i| send_3wire_bit(val>>i)}
    adc16_controller[0] = IDLE_3WIRE
    self
  end

  ZDOK_SHIFT = 28 # :nodoc:
  ZDOK_MASK  =  3 # :nodoc: after left shift by ZDOK_SHIFT

  # Return the ZDOK pinout revision for which the ADC16 design was built (0, 1,
  # or 2).
  #
  #   1 = ZDOK pinout revision 1 (programs ADCs over ribbon cable)
  #   2 = ZDOK pinout revision 2 (programs ADCs via ZDOK connectors)
  def zdok_rev
    zr = (adc16_controller[0] >> ZDOK_SHIFT) & ZDOK_MASK
    # Older gateware did not set these bits, so 0 means 1
    zr = 1 if zr == 0
    zr
  end

  LOCKED_SHIFT = 24 # :nodoc:
  LOCKED_MASK  =  3 # :nodoc: after left shift by LOCKED_SHIFT

  # Return the locked status of the ADC board(s).
  #
  #   0 = only no ADC clocks are locked (BAD)
  #   1 = only ADC0 clock is locked (OK if num_adcs <= 4, BAD if num_adcs >=5)
  #   2 = only ADC1 clock is locked (BAD since ADC0 clock is always needed)
  #   3 = both ADC clocks are locked (OK, but weird if num_adcs <=4)
  def locked_status
    (adc16_controller[0] >> LOCKED_SHIFT) & LOCKED_MASK
  end

  NUM_ADCS_SHIFT =  20 # :nodoc:
  NUM_ADCS_MASK  = 0xF # :nodoc: after left shift by NUM_ADCS_SHIFT

  # Returns the number of ADCS for which the gateware was built (currently
  # limited to 4 or 8).
  def num_adcs
    (adc16_controller[0] >> NUM_ADCS_SHIFT) & NUM_ADCS_MASK
  end

  ROACH2_REV_SHIFT = 16 # :nodoc:
  ROACH2_REV_MASK  =  3 # :nodoc: after left shift by ROACH2_REV_SHIFT

  # Returns the ROACH2 revision for which the ADC16 design was built (1 or 2).
  def roach2_rev
    (adc16_controller[0] >> ROACH2_REV_SHIFT) & ROACH2_REV_MASK
  end

  # Returns true is ADC16 gateware supports demultiplexing modes.
  # Demultiplexing modes are used when running the ADC16 in dual and quad
  # channel configurations.  See #demux and #demux= for more info.
  def supports_demux?
    # The W bit cannot be set to 1 if the ADC16 gateware supports demux modes.
    adc16_controller[1] |= 0x0400_0000
    return (adc16_controller[1] & 0x0400_0000) == 0
  end

  # Demux mode value for quad channel (per chip) operation
  # (16 channels @ 1 ADC sample per FPGA fabric cycle)
  DEMUX_BY_1 = 1

  # Demux mode value for dual channel (per chip) operation
  # (8 channels * 2 ADC samples per FPGA fabric cycle)
  DEMUX_BY_2 = 2

  # Demux mode value for single channel (per chip) operation
  # (4 channels * 4 ADC samples per FPGA fabric cycle)
  DEMUX_BY_4 = 4

  DEMUX_SHIFT = 24 # :nodoc:
  DEMUX_MASK  =  3 # :nodoc:

  # Returns the current demux mode.  If the gateware does not support demux
  # modes, then this will always return DEMUX_BY_1.  This method will always
  # return one of: DEMUX_BY_1, DEMUX_BY_2, or DEMUX_BY_4.
  def demux
    return DEMUX_BY_1 unless supports_demux?
    mode = (adc16_controller[1] >> DEMUX_SHIFT) & DEMUX_MASK
    case mode
    when 1; DEMUX_BY_2
    when 2; DEMUX_BY_4
    else    DEMUX_BY_1
    end
  end

  # Sets the current demux mode.  Raises exception if the gateware does not
  # support demux modes and a mode other than DEMUX_BY_1 is being requested.
  # Raises an exception if +mode+ is something other than DEMUX_BY_1,
  # DEMUX_BY_2, or DEMUX_BY_4.
  #
  # Note that setting the demux mode here only affects the demultiplexing of
  # the data from the ADC before presenting it to the FPGA fabric.  The
  # demultiplexing mode set does NOT set the "mode of operation" of the ADC
  # chips.  That must be done by the user when initializing the ADC16 chips
  # because it requires a software power down of the ADC chip.  The user is
  # responsible for ensuring that the "mode of operation" set in the ADC chips
  # at initialization time is consistent with the demux mode set using this
  # method.  Mismatches will result in improper interpretation of the data.
  def demux=(mode)
    case mode
    when DEMUX_BY_1
      adc16_controller[1] |= ((4+0) << DEMUX_SHIFT)
    when DEMUX_BY_2, DEMUX_BY_4
      if supports_demux?
        adc16_controller[1] |= ((4+mode/2) << DEMUX_SHIFT)
      else
        raise 'current gateware does not support demux modes'
      end
    else
      raise "invalid demux mode (#{mode})"
    end
  end

  # Performs a reset of all ADCs selected by +chip_select+.
  def adc_reset
    setreg(0x00, 0x0001) # reset
  end

  # Performs a power cycle of all ADCs selected by +chip_select+.
  def adc_power_cycle
    setreg(0x0f, 0x0200) # Powerdown
    # Power up one chip at a time
    cs_orig = @chip_select
    num_adcs.times do |i|
      next unless (cs_orig & (1<<i)) != 0
      @chip_select = (1<<i)
      setreg(0x0f, 0x0000) # Powerup
    end
    # Restore original cs value
    @chip_select = cs_orig
  end

  # Initializes the ADCs that are enabled by +chip_select+.  The +opts+ Hash
  # consists of integer keys and values.  The keys are register addresses to
  # which the corresponding values will be written.  A few "special" symbols
  # keys are also supported:
  #
  #   :phase_ddr (value ignored) == Set phase_ddr to 0 degrees
  #
  # ADC initialiation consists of resetting the ADC, programming any registers
  # desired, then power cycling.  See the ADC datasheet for more details.
  def adc_init(opts={})
    raise 'FPGA not programmed' unless programmed?
    adc_reset
    if opts.has_key? :phase_ddr
      opts[0x42] = 0x60
      opts.delete(:phase_ddr)
    end

    # Set register 0x50 to 0x30 (Vcom drive strength to max), unless the user
    # specified it explicitly.
    opts[0x50] = 0x30 unless opts.has_key? 0x50

    opts.each {|addr,val| setreg(addr, val) if (0x00..0x56) === addr}
    adc_power_cycle
    progdev @opts[:bof] if @opts[:bof]
  end

  # Set output data endian-ness and binary format of all ADCs selected by
  # +chip_select+.  If +msb_invert+ is true, then invert msb (i.e. output 2's
  # complement (else straight offset binary).  If +msb_first+ is true, then
  # output msb first (else lsb first).
  #
  # Note that the ADC yellow block expects the ADC defaults for data
  # endian-ness and binary format, so this method is mostly intended for low
  # level devlopment.  The ADC chip outputs "straight offset binary" format by
  # default, but the ADC16 yellow block converts that to two's complement form.
  def data_format(invert_msb=false, msb_first=false)
    val = 0x0000
    val |= invert_msb ? 4 : 0
    val |= msb_first ? 8 : 0
    setreg(0x46, val)
  end

  # Selects a test pattern or sampled data for all ADCs selected by
  # +chip_select+.  +ptn+ can be any of:
  #
  #   :ramp            Ramp pattern 0-255
  #   :deskew (:eye)   Deskew pattern (10101010)
  #   :sync (:frame)   Sync pattern (11110000)
  #   :custom1         Custom1 pattern
  #   :custom2         Custom2 pattern
  #   :dual            Dual custom pattern
  #   :none            No pattern (sampled data)
  #
  # Default is :ramp.  Any value other than shown above is the same as :none
  # (i.e. pass through sampled data).
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

  # Convenience for <code>enable_pattern :none</code>.
  def clear_pattern;  enable_pattern :none;   end
  # Convenience for <code>enable_pattern :ramp</code>.
  def ramp_pattern;   enable_pattern :ramp;   end
  # Convenience for <code>enable_pattern :deskew</code>.
  def deskew_pattern; enable_pattern :deskew; end
  # Convenience for <code>enable_pattern :sync</code>.
  def sync_pattern;   enable_pattern :sync;   end
  # Convenience for <code>enable_pattern :custom</code>.
  def custom_pattern; enable_pattern :custom; end
  # Convenience for <code>enable_pattern :dual</code>.
  def dual_pattern;   enable_pattern :dual;   end
  # Convenience for <code>enable_pattern :none</code>.
  def no_pattern;     enable_pattern :none;   end

  # Set the "custom 1" pattern from the lowest 8 bits of +bits+.
  def custom1=(bits)
    setreg(0x26, (bits&0xff) << 8)
  end

  # Set the "custom 2" pattern from the lowest 8 bits of +bits+.
  def custom2=(bits)
    setreg(0x27, (bits&0xff) << 8)
  end

  SNAP_REQ = (1<<16)    # :nodoc:
  BITSLIP_SHIFT = 8     # :nodoc:
  DELAY_TAP_MASK = 0x1F # :nodoc:

  # Performs a bitslip operation on all SERDES blocks for chips given by
  # +*chips+.
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
  #
  # For a given channel, the even samples are from lane "a", the odd from lane
  # "b".
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
  end

  # Sets the delay tap for ADC +chip+ to +tap+ for channels specified in
  # +chans+ bitmask.  Bits 0-3 select the "a" lane of channels 0-3.  Bits 4-7
  # select the "b" lane of channels 0-3.  For example, a +chans+ value of 33
  # (0b0010_0001) would set the delay taps for ADC +chip+ channel 0 lane "a"
  # and channel 1 lane "b" to +tap+.
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

  # Tests a tap setting for an ADC chip.  Used by #walk_taps.
  # Returns a four element array.  Each element represents one channel and is
  # itself a two element array containing error counts for the channel's lanes.
  # A zero value means no errors for the corresponding channel/lane of the
  # given chip at the given delay tap.
  #
  # For example, if +chip+ is :c and +tap+ is 12 and test_tap returns
  # <tt>[[0,0],[0,0],[0,9],[0,0]]</tt> it means that all channels and lanes of
  # chip C worked OK at tap setting 12 except for channel index 2 lane b (aka
  # "C3b") which had 9 errors.
  def test_tap(chip, tap, opts={})
    # Allow caller to override default opts
    opts = {
      :expected => 0x2a,
      :num_iters => 1,
      :verbose => false
    }.merge!(opts)

    # Convert lowest 8 bits of opts[:expected] from unsigned byte to signed integer
    expected  = opts[:expected] & 0xff
    expected -= 256 if expected >= 128

    # Set tap
    delay_tap(chip, tap)

    # Accumulate error counts for opts[:num_iters] iterations
    chan_counts = [[0,0],[0,0],[0,0],[0,0]]
    opts[:num_iters].times do |iter|
      # Get snap data and convert to 8-by-N matrix of bytes
      d = snap(chip, :n=>1024).reshape(8,true)
      # Examine each channel in snap data and accumulate data
      4.times do |chan|
        # Check for expected value
        even_errcount = d[chan  , nil].ne(expected).where.length # "even" samples
        odd_errcount  = d[chan+4, nil].ne(expected).where.length  # "odd"  samples
        chan_counts[chan][0] += even_errcount
        chan_counts[chan][1] += odd_errcount
        if opts[:verbose] == :very
          print "chip #{chip} "
          print "tap #{tap} "
          print "chan #{chan} "
          print "iter #{iter} "
          puts "err_counts [#{even_errcount}, #{odd_errcount}]"
        end
      end # for each channel
    end # for num_iters

    chan_counts
  end

  # Walks delay tap values for a given ADC chip.
  def walk_taps(chip, opts={})
    # Allow caller to override default opts
    opts = {
      :expected => 0x2a,
      :num_iters => 1,
      :verbose => false
    }.merge!(opts)

    # Set deskew pattern
    deskew_pattern

    # Test taps 0 and 31.  If either extreme tap setting is good for any
    # lane of any channel, we assume that the "eye" of the expected pattern
    # will not be fully crossed by sweeping the delay, so we bitslip the chip
    # to shift the expected pattern by an odd number of bits (either right 1 or
    # left 3).
    chan_counts_0  = test_tap(chip,  0, opts)
    chan_counts_31 = test_tap(chip, 31, opts)
    if [chan_counts_0, chan_counts_31].flatten.index(0)
      puts "bitslipping chip #{ADC16.chip_name(chip)} to sample eye pattern better" if opts[:verbose]
      bitslip(chip)
    end

    # good_tap_ranges has four elements, one element for each channel;
    # each channel's element has two elements, one for each lane.
    # Each lane element is an Array that will contain ranges indicating good
    # taps.
    good_tap_ranges = [[[],[]], [[],[]], [[],[]], [[],[]]]
    counts = [[], [], [], []]

    # Test all taps
    (0..31).each do |tap|
      chan_counts = test_tap(chip, tap, opts)
      # Check each channel's chan_counts
      4.times do |chan|
        counts[chan][tap] = chan_counts[chan]
        2.times do |lane|
          # If good
          if chan_counts[chan][lane] == 0
            last_range = good_tap_ranges[chan][lane][-1]
            # If no range yet or new range
            if last_range.nil? || tap > last_range.end + 1
              good_tap_ranges[chan][lane] << (tap..tap)
            else
              good_tap_ranges[chan][lane][-1] = (last_range.first..tap)
            end
          end # if good
        end # lanes
      end # chans
    end # taps

    # Set delay taps to middle of the good range
    set_taps = [[],[],[],[]]
    4.times do |chan|
      2.times do |lane|
        good_chan_tap_ranges = good_tap_ranges[chan][lane]
        if good_chan_tap_ranges.empty?
          puts "chip #{ADC16.chip_name(chip)} " \
               "chan #{chan+1} lane #{lane} "   \
               "no good taps found" if opts[:verbose]
          next
        end

        # Find longest range
        best_chan_tap_range = good_chan_tap_ranges.max_by {|r| r.count}
        # TODO Print warning if good range is too small?
        # Compute midpoint
        best_chan_tap = (best_chan_tap_range.first + best_chan_tap_range.last) / 2
        # Set delay tap to midpoint
        delay_tap(chip, best_chan_tap, 1<<(chan+4*lane))
        puts "chip #{ADC16.chip_name(chip)} "   \
             "chan #{chan+1} lane #{lane} "     \
             "setting tap=#{best_chan_tap} "    \
             "from #{good_chan_tap_ranges.inspect}" if opts[:verbose]
        set_taps[chan][lane] = best_chan_tap
      end
    end

    [set_taps, counts]
  end

  # Enables the sync pattern and then bitslips the SERDES blocks for one or more
  # ADC chips to capture expected sync pattern.  +opts+ is a Hash that supports
  # the following keys (shown with default values):
  #
  #   :chips => [:a, :b, :c, :d, :e, :f, :g, :h]
  #     - Chips to calibrate
  #
  #   :sync_expected => 0x70
  #     - Expected value of sync pattern (leave at default except for testing)
  def sync_chips(opts={})
    # Allow caller to override default opts
    opts = {
      :chips => [:a, :b, :c, :d, :e, :f, :g, :h],
      :sync_expected => 0x70
    }.merge!(opts)

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

  # Calibrates the SERDES blocks for one or more ADC chips.  +opts+ is a Hash
  # that supports the following keys (shown with default values):
  #
  #   :chips => [:a, :b, :c, :d, :e, :f, :g, :h]
  #     - Chips to calibrate
  #
  #   :deskew_expected => 0x2a
  #     - Expected value of deskew pattern (leave at default except for testing)
  #
  #   :sync_expected => 0x70
  #     - Expected value of sync pattern (leave at default except for testing)
  #
  #   :num_iters => 1
  #     - Number of snapshots to accumulate calibration data.
  #
  #   :verbose => false
  #     - Output informative messages if +true+.
  #     - Output verbose messages if <code>:very</code>.
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
    # Select only those chips that are supported/used
    opts[:chips] = opts[:chips].select do |c|
      (0...num_adcs) === ADC16.chip_num(c)
    end

    # Create :expected alias for :deskew_expected so that opts can be passed to walk_taps
    opts[:expected] = opts[:deskew_expected] unless opts[:expected]

    # Error out if ADC0 is not locked
    raise 'ADC0 clock not locked' if (locked_status&1) == 0
    # If num_adcs > 4 and ADC1 clock is not locked and opts[:chips].reject! for
    # chips greater than 3 actually rejected any chips, issue warning
    if num_adcs > 4 && (locked_status&2) == 0 \
    && opts[:chips].reject! {|c| ADC16.chip_num(c) > 3}
        warn 'warning: ADC1 clock not locked, will not calibrate its chips'
    end

    # Convert to chip names
    opts[:chips].map! {|c| ADC16.chip_name(c)}
    puts "calibrating chips #{opts[:chips].inspect}" if opts[:verbose]

    # Walk delay taps (sets deskew pattern)
    opts[:chips].each do |chip|
      walk_taps(chip, opts)
      yield ADC16.chip_name(chip) if block_given?
    end

    # Sync chips
    sync_chips(opts)
  end

  # Estimates the FPGA clock frequency from consecutive readings of
  # sys_clkcounter.  Returns results in Hz by default; pass 1e6 for +scale+ to
  # get MHz etc.  +secs+ is how long to wait between readings of
  # sys_clkcounter.  Waiting more than one wrap around will give invalid
  # results.
  #
  # It could be argued that this method belongs in KATCP::RoachClient.
  def est_clk_freq(secs=1, scale=1)
    tic = sys_clkcounter
    sleep secs
    toc = sys_clkcounter
    (toc - tic) % (1<<32) / scale / secs
  end

  # Returns Hash describing RCS info.  The Hash contains two keys, +:app+ and
  # +:lib+.  Each key maps to either a Hash which either has one key :time or
  # the three keys +:type+, +:dirty+, and +:rev+.  If the Hash has the :time
  # key, its value is a Fixnum of the 31 bit timestamp representing the time
  # in seconds since the Unix epoch.  If the Hash has the three keys +:type+,
  # +:dirty+, and +:rev+, their values are as described here:
  #
  #   :type  => :git or :svn indicating the revision control system
  #
  #   :dirty => true or false indicating whether the working copy had
  #             uncommitted changes.
  #
  #   :rev   => String representing the decimal Subversion revision number or
  #             the first 7 hex digits of the Git commit id.
  #
  # Normally the revision info is read from the RCS registers only one.  The
  # +reload+ parameter can be passed as +true+ to force a reload (e.g. if the
  # FPGA is reprogrammed with a new version of the ROACH2 F engine design).
  #
  # It could be argued that this method belongs in KATCP::RoachClient.
  def rcs(reload=false)
    @revinfo ||= {}
    @revinfo[:app] ||= {}
    @revinfo[:lib] ||= {}
    if (reload || @revinfo[:app].empty?) && programmed? && respond_to?(:rcs_app)
      app_info = rcs_app
      if app_info & 0x8000_0000 != 0
        # Timestamp
        @revinfo[:app][:time ] = app_info & ~0x8000_0000
      else
        @revinfo[:app][:dirty] = (app_info & 0x1000_0000) != 0
        if (app_info & 0x4000_0000) == 0
          @revinfo[:app][:type ] = :git
          @revinfo[:app][:rev  ] = '%07x' % (app_info & 0x0fff_ffff)
        else
          @revinfo[:app][:type ] = :svn
          @revinfo[:app][:rev  ] = '%d'   % (app_info & 0x0fff_ffff)
        end
      end
    end
    if (reload || @revinfo[:lib].empty?) && programmed? && respond_to?(:rcs_lib)
      lib_info = rcs_lib
      if lib_info & 0x8000_0000 != 0
        # Timestamp
        @revinfo[:lib][:time ] = lib_info & ~0x8000_0000
      else
        @revinfo[:lib][:dirty] = (lib_info & 0x1000_0000) != 0
        if (lib_info & 0x4000_0000) == 0
          @revinfo[:lib][:type ] = :git
          @revinfo[:lib][:rev  ] = '%07x' % (lib_info & 0x0fff_ffff)
        else
          @revinfo[:lib][:type ] = :svn
          @revinfo[:lib][:rev  ] = '%d'   % (lib_info & 0x0fff_ffff)
        end
      end
    end
    @revinfo
  end # #rcs
  alias :scm :rcs

end # class ADC16

require 'adc16/version'
