import cocotb
from cocotb.triggers import RisingEdge
from cocotb.triggers import Timer
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from params import Params

USER_WB_BASEADDR    = 0x30020000

BLOCK_CFG_ADDR      = 0x30010000
VRNODE_CFG_ADDR     = 0x30011000
HRNODE_CFG_ADDR     = 0x30012000
RST_CFG_ADDR        = 0x3001A000
CLK_CFG_ADDR        = 0x3001E000
EFUSE_CFG_ADDR      = 0x30030000

CONFIG_DELAY_TICKS  = 1
FREQ_KHZ            = 3000

block_fw = []
vrnode_fw = []
hrnode_fw = []

def listToString(s): 
    # initialize an empty string
    str1 = "" 
    # traverse in the string  
    for ele in s: 
        str1 += ele  
    # return string  
    return str1 

class WishboneRegs:
    def __init__(self, dut, base):
        self.dut = dut
        self.base = base
        self.clk = self.dut.wb_clk_i
        self.wbs = WishboneMaster(self.dut, "wbs", self.clk, width=32, timeout=10,
            signals_dict={"cyc":  "cyc_i",
                          "stb":  "stb_i",
                          "we":   "we_i",
                          "adr":  "adr_i",
                          "datwr":"dat_i",
                          "datrd":"dat_o",
                          "ack":  "ack_o" })
        
    async def read(self, addr):
        wbres = await self.wbs.send_cycle([WBOp(adr=addr)]) 
        return wbres[0].datrd
        
    async def write(self, addr, dat):
        wbres = await self.wbs.send_cycle([WBOp(adr=addr, dat=dat)]) 
        
class WishboneCfgLoader:
    def __init__(self, wb):
        self.wb = wb
        self.clk = self.wb.dut.wb_clk_i
        self.rst = self.wb.dut.wb_rst_i
        cocotb.fork(Clock(self.clk, round(10**6 / FREQ_KHZ), units="ns").start())
        
    # Reset process
    async def reset(self):
        self.rst.value = 1
        await cocotb.triggers.ClockCycles(self.clk, 10)
        await cocotb.triggers.Timer(50, "ns")
        self.rst.value = 0
        await RisingEdge(self.clk)
        await RisingEdge(self.clk)

    async def load_efuse_data(self, dat, addr):
        await self.wb.write(EFUSE_CFG_ADDR + addr, dat)       
        
    async def load_lb_bit(self, dat):
        await self.wb.write(BLOCK_CFG_ADDR, dat)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 1)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 0)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)

    async def load_vr_bit(self, dat):
        await self.wb.write(VRNODE_CFG_ADDR, dat)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 2)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 0)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)

    async def load_hr_bit(self, dat):
        await self.wb.write(HRNODE_CFG_ADDR, dat)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 4)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
        await self.wb.write(CLK_CFG_ADDR, 0)
        await cocotb.triggers.ClockCycles(self.clk, CONFIG_DELAY_TICKS)
    
    async def fabric_set(self):
        await self.wb.write(RST_CFG_ADDR, 0x1) # Release pads (#WARNING deside what real order do we need here?)
        await self.wb.write(RST_CFG_ADDR, 0x0) # Global reset deassert

    async def fabric_reset(self):
        await self.wb.write(RST_CFG_ADDR, 0x3)

    async def wait_for(self, nck):
        await cocotb.triggers.ClockCycles(self.clk, nck)
        
    async def wb_reset(self):
        await self.wb.write(RST_CFG_ADDR, 0x8)
        await cocotb.triggers.ClockCycles(self.clk, 8)
        await self.wb.write(RST_CFG_ADDR, 0x0)

    async def load_fw_efuse(self, BITSTREAM):
        buf_line=[]
        with open(BITSTREAM) as f:
            for line in f:
                buf = (line.replace("\n", "").replace(" ", ""))
                buf_line += buf

        #buf_line.reverse()
        fw_lim = len(buf_line)
        if (fw_lim % 8) > 0 :
            for i in range(int(fw_lim % 8)):
                buf_line.append('0')
        fw_efuse=[]
        for i in range(int(len(buf_line)/8)):
            rev_buf = buf_line[i*8 : (i+1)*8]
            rev_buf.reverse()
            fw_efuse.append(int(listToString(rev_buf),2))
            
        for i in range(len(fw_efuse)):
            await self.load_efuse_data(fw_efuse[i], i)

    async def load_fw(self, BITSTREAM):
        i = 0
        block_fw = []
        vrnode_fw = []
        hrnode_fw = []
        
        # Read params config file
        p = Params("../../arch/params.cfg")
        C_BD = p.BLOCK_CFGCHAIN_LEN
        C_VD = p.VRNODE_CFGCHAIN_LEN
        C_HD = p.HRNODE_CFGCHAIN_LEN        
        
        with open(BITSTREAM) as f:
            for line in f:
                
                buf_line = line.replace("\n","").split(" ")
                
                if i < C_BD:
                    block_fw.append(int(listToString(reversed(buf_line[0])),2))
                if i < C_VD:
                    vrnode_fw.append(int(listToString(reversed(buf_line[1])),2))
                if i < C_HD:
                    hrnode_fw.append(int(listToString(reversed(buf_line[2])),2))  
                
                i += 1
                
        for regs in block_fw:
            await self.load_lb_bit(regs)
            
        for regs in vrnode_fw:
            await self.load_vr_bit(regs)        

        for regs in hrnode_fw:
            await self.load_hr_bit(regs)            
                  
