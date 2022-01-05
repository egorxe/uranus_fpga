import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from wishbone_loader_cocotb import *

import random

USER_WB_BASEADDR    = 0x30F00000

BLOCK_CFG_ADDR      = 0x30100000
VRNODE_CFG_ADDR     = 0x30200000
HRNODE_CFG_ADDR     = 0x30300000
CLK_CFG_ADDR        = 0x30E00000
RST_CFG_ADDR        = 0x30A00000

CNT_ADDR            = 0x30F000F0

MEM_WIDTH           = 32
MEM_DEPTH           = 2**2

class WishboneMemTest:
    def __init__(self, wb):
        self.wb = wb
        self.clk = self.wb.dut.wb_clk_i
                
    async def write_mem_data(self, addr, data):
        await self.wb.write(USER_WB_BASEADDR + addr, data)

    async def read_mem_data(self, addr):
        val = await self.wb.read(USER_WB_BASEADDR + addr)
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
    await loader.load_fw("firmware.bit")

    # Launch FPGA fabric
    await loader.fabric_set()        
    
    dut.log.info("Firmware loading finished!")
    
    await loader.wb_reset()
    
    dut.log.info("Design ready for test!")
    
    model_ram = []
    
    dut.log.info("Init mem with random data...")
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
        
