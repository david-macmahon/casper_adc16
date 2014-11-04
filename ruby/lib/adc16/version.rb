#--
# Define ADC16::VERSION
#++

# Create ADC16 class if it is not already defined.  The file adc16.rb requires
# this file *after* it has defined the ADC16 class.  The definition here does
# not have the same superclass as the definition in adc16.rb, so the definition
# here is really intended only for special circumstances such as the creation
# of a gemspec (see Rakefile at the top level).  Having a simpler definition
# for the standalone case simplifies gem packaging.  The only way this can
# cause problems is if the user explicitly requires "adc16/version" then
# requires "adc16" (so don't do that!).
class ADC16; end unless Module.const_defined? 'ADC16' # :nodoc:

# Version string of ADC16 extension and gem
ADC16::VERSION = "0.4.1"
