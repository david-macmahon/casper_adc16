# Requires the `katcp` gem and adds KATCP specific methods to ADC16 class,
# which extends KATCP::RoachClient.

require 'rubygems'

# We need a katcp version in which RoachClient defines DEVICE_TYPEMAP.
# That was introduced in katcp 0.1.10.
gem 'katcp', '~> 0.1.10'
require 'katcp'

# Define ADC16 class under KATCP::RoachClient and include KATCP specific
# functionality.
class ADC16 < KATCP::RoachClient

  # Programs FPGA.  If bof is not given, any BOF file passed to "#new" will be
  # used.  Passing +nil+ will deprogram the FPGA.
  def progdev(bof=@opts[:bof])
    puts 'Programming!'
    super(bof)
  end
  
end

# Add in the bulk of the ADC16 implementaion
# TODO Add the functionality via module mixin rather than re-opening class.
require 'adc16/adc16'
