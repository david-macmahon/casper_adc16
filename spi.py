import numpy as np



class SPI():
    def __init__(self,fpga,cs=0x3c,sda=0x40,scl=0x80):
        self.u = fpga
        self.cs = cs
        self.sda = sda
        self.scl = scl
        self.reset()

    def reset(self):
        self.write(0x00,0x0000)

    def select(self, chip):
        if chip<0:
            self.cs=0x3c
        else:
            self.cs=((0x04)<<chip)&(0x3c)
        
    def out(self,cs=True,scl=True,sda=False):
        word = 0
        if cs:
            word |= self.cs
        if scl:
            word |= self.scl
        if sda:
            word |= self.sda
            
    def write_state(self,state):
        state = state<<24
        #print hex(state)
        self.u.write_int('adcleda_controller',state,offset=0)
        
    def send_bit(self,bit):
        if bit:
            out = self.sda
        else:
            out = 0
        self.write_state(out) # clock low, cs low
        self.write_state(out | self.scl) # clock high, cs low
        
    def write(self,addr,data):
        addr = np.atleast_1d(addr)
        data = np.atleast_1d(data)
        
        if addr.shape[0] != data.shape[0]:
            raise Exception("address and data arrays must be same length")
        
        for k in range(addr.shape[0]):
            for m in range(8):
                bit = (addr[k]>>(7-m)) & 0x01
                self.send_bit(bit)
            for m in range(16):
                bit = (data[k]>>(15-m)) & 0x01
                self.send_bit(bit)
            self.write_state(self.cs | self.scl)
