# Requires the `tapcp` gem and adds TAPCP specific methods to ADC16 class,
# which extends TAPCP::Client.

require 'tapcp'

# Define ADC16 class under TAPCP::Client and include TAPCP specific
# functionality.
class ADC16 < TAPCP::Client

  # Does nothing, exists for KATCP compatibility
  def progdev(bof=nil)
    puts 'Not programming!'
  end
  
end

# Add in the bulk of the ADC16 implementaion
# TODO Add the functionality via module mixin rather than re-opening class.
require 'adc16/adc16'
