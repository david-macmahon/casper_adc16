import numpy as np
from corr import katcp_wrapper
from spi import SPI
import time

class Test():
    def __init__(self):
        self.verbose = True
        self.u = katcp_wrapper.FpgaClient('roach2')
        print 'Connected...'
        time.sleep(1)
        self.u.progdev('tclk_2012_Oct_15_1635.bof')
        print 'Programmed...'
        self.s = SPI(self.u)

        self.tap = 0

        ## Make sure that SPI interface is flushed
        ## and initialize
        self.start()
        
    def reset(self):
        self.s.write(0x00,0x0001) # reset

    def select(self, chip):
        self.s.select(chip)

    def power_cycle(self):
        self.s.write(0x0f,0x0200) # Powerdown
        self.s.write(0x0f,0x0000) # Powerup

    def start(self):
        print 'Beginning ADC power cycling'

        print 'Resetting ADC'
        self.reset() # reset
        print 'Reset done'

        print 'Power down ADC'
        self.power_cycle()
        print 'Power cycling done'

    def commit(self):
        self.power_cycle()

    def clear_pattern(self):
        self.s.write(0x45,0x0000) # Clear skew,deskew
        self.s.write(0x25,0x0000) # Clear ramp
        #self.commit()

    def ramp_pattern(self):
        self.clear_pattern()
        self.s.write(0x25,0x0040) # Enable ramp
        #self.commit()

    def deskew_pattern(self):
        self.clear_pattern()
        self.s.write(0x45,0x0001)
        #self.commit()

    def sync_pattern(self):
        self.clear_pattern()
        self.s.write(0x45,0x0002)
        #self.commit()

    def reset_all(self):
        ## Clear
        reg = self.u.read_int('adcleda_controller')
        reg = reg & 0xfffffffb        
        self.u.write_int('adcleda_controller',reg, offset=1, blindwrite=True)
        reg = reg | 0x00000004        
        self.u.write_int('adcleda_controller',reg, offset=1, blindwrite=True)
        time.sleep(1)
        reg = reg & 0xfffffffb       
        self.u.write_int('adcleda_controller',reg, offset=1, blindwrite=True)

    def get_channel(self):
        data = self.u.snapshot_get('fifo_data_a',man_trig=True)['data']
        x = np.fromstring(data,dtype='>i4')
        y = x.astype('uint8')
        return y

    def get_data(self):
        data = []

        temp = np.fromstring(self.u.snapshot_get('fifo_data',man_trig=True)['data'],dtype=np.uint8)

        data.append(self.process_data(temp[range(0,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(1,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(2,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(3,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(4,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(5,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(6,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(7,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(8,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(9,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(10,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(11,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(12,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(13,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(14,temp.size,16)].astype('uint8')))
        data.append(self.process_data(temp[range(15,temp.size,16)].astype('uint8')))

        return data

    def bit_slip(self, channel):
        ## Write to bitslip
        reg = self.u.read_int('adcleda_controller')
        reg = reg ^ 0x00000780        
        self.u.write_int('adcleda_controller',reg, offset=1)
        time.sleep(1)
        reg = reg ^ 0x00000780        
        self.u.write_int('adcleda_controller',reg, offset=1)

    def flip_channel(self, channel):
        ## Write to channel flip
        reg = self.u.read_int('adcleda_controller')
        reg = reg ^ 0x00000071        
        self.u.write_int('adcleda_controller',reg, offset=1)

    def process_data(self, data):
        #print 'Before:'
        #print ['%02x' % y for y in data[:8]]
        out_p = []
        for num in range(0,len(data)-1):
            y = data[num]&0xff
            y = ((y&0x08)>>3)|((y&0x04)>>1)|((y&0x02)<<1)|((y&0x01)<<3)|((y&0x80)>>3)|((y&0x40)>>1)|((y&0x20)<<1)|((y&0x10)<<3)
            out_p.append(y)
        #print '\nAfter:'
        #print ['%02x' % y for y in out_p[:8]]
        return out_p

    def show_data(self, data):
        plot(data)

    def inc_tap(self):
        self.tap = self.tap + 1
        y = (self.tap)&0x1f
        #y = (((self.tap)&0x10)>>4)|(((self.tap)&0x08)>>2)|((self.tap)&0x04)|(((self.tap)&0x02)<<2)|(((self.tap)&0x01)<<4)
        s = (y<<11)|(0x00000000)
        self.u.write_int('adcleda_controller',s,offset=1)
        time.sleep(1)
        s = (y<<11)|(0xffff0000)
        self.u.write_int('adcleda_controller',s,offset=1)
        time.sleep(1)
        s = (y<<11)|(0x00000000)
        self.u.write_int('adcleda_controller',s,offset=1)

    #def calibrate(self):
    #    self.
        