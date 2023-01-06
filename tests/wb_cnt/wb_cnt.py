import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from wishbone_loader_cocotb import *

USER_WB_BASEADDR    = 0x30020000

CNT_ADDR            = USER_WB_BASEADDR + 0xF0

class WishboneCntTest:
    def __init__(self, wb):
        self.wb = wb
        self.clk = self.wb.dut.wb_clk_i
                
    async def increment(self):
        await self.wb.write(CNT_ADDR, 0)

    async def get_cnt_val(self):
        val = await self.wb.read(CNT_ADDR)
        return val

@cocotb.test()
async def run_test(dut):
    # Create wishbone access helpers
    wb = WishboneRegs(dut, USER_WB_BASEADDR)
    loader = WishboneCfgLoader(wb)
    test = WishboneCntTest(wb)

    # ~ vccd1.value = 1
    # ~ vccd2.value = 0
    # ~ vdda1.value = 1
    # ~ vdda2.value = 1
    # ~ vssa1.value = 0
    # ~ vssa2.value = 0
    # ~ vssd2.value = 0
    
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
    
    # vccd1 = dut.vccd1
    # vccd2 = dut.vccd2
    # vdda1 = dut.vdda1
    # vdda2 = dut.vdda2
    # vssa1 = dut.vssa1
    # vssa2 = dut.vssa2
    # vssd2 = dut.vssd2
    

    
    dut.log.info("Design ready for test!")
    
    dut.log.info("Checking that initial value is correct...")
    cur_cnt = await test.get_cnt_val()
    assert cur_cnt == 0
    dut.log.info("Ok")
    
    dut.log.info("Checking that one increment works fine...")
    await test.increment()
    cur_cnt = await test.get_cnt_val()
    assert cur_cnt == 1    
    dut.log.info("Ok")
    
    dut.log.info("Cheking that reset works fine...")
    await loader.wb_reset()
    cur_cnt = await test.get_cnt_val()
    assert cur_cnt == 0
    dut.log.info("Ok")
    
    dut.log.info("Checking multiple increment...")
    for i in range(10):
        await test.increment()
    cur_cnt = await test.get_cnt_val()
    assert cur_cnt == 10
    dut.log.info("Ok")
    
    dut.log.info("Checking overflow...")
    await loader.wb_reset()
    for i in range(129):
        await test.increment()
    cur_cnt = await test.get_cnt_val()
    assert cur_cnt == 1
    dut.log.info("Ok")      
            
