import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from wishbone_loader_cocotb import *

import random

USER_WB_BASEADDR    = 0x30020000
EFUSE_WB_ADDR       = 0x30030000
BLOCK_CFG_ADDR      = 0x30010000
VRNODE_CFG_ADDR     = 0x30011000
HRNODE_CFG_ADDR     = 0x30012000
RST_CFG_ADDR        = 0x3001A000
CLK_CFG_ADDR        = 0x3001E000

MEM_WIDTH           = 8
MEM_DEPTH           = 1152

class WishboneMemTest:
    def __init__(self, wb):
        self.wb = wb
        self.clk = self.wb.dut.wb_clk_i
                
    async def write_mem_data(self, addr, data):
        await self.wb.write(EFUSE_WB_ADDR + addr, data)

    async def read_mem_data(self, addr):
        val = await self.wb.read(EFUSE_WB_ADDR + addr)
        return val

@cocotb.test()
async def run_test(dut):
    # Create wishbone access helpers
    wb = WishboneRegs(dut, USER_WB_BASEADDR)
    loader = WishboneCfgLoader(wb)
    test = WishboneMemTest(wb)
    
    dut.log.info("Starting firmware loading...")
    
    # Reset regs
    await loader.reset()
    
    # Reset FPGA fabric
    await loader.fabric_reset() 
    
    # Load FPGA firmware
    #await loader.load_fw("firmware.bit")

    # Launch FPGA fabric
    await loader.fabric_set()        
    
    dut.log.info("Firmware loading finished!")
    
    await loader.wb_reset()
    
    dut.log.info("Design ready for test!")
    
    model_ram = []
    
    dut.log.info("Init efuse with random data...")
    for i in range(MEM_DEPTH):
        buf = random.randint(0, (2**MEM_WIDTH)-1)
        await test.write_mem_data(i, buf)
        model_ram.append(buf)
        
    dut.log.info("Done!")
    
    dut.log.info("Test data readback...")
    for i in range(MEM_DEPTH):
        assert model_ram[i] == await test.read_mem_data(i)
        # ~ await test.read_mem_data(i)
        
    dut.log.info("Done!")
        
