import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from wishbone_loader_cocotb import *

USER_WB_BASEADDR    = 0x30020000
EFUSE_WTIMER_ADDR   = 0x30030801
EFUSE_RTIMER_ADDR   = 0x30030800



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
    io_in = dut.io_in
    la_data_out = dut.la_data_out
    dut.io_in.value = 0

    try:
        dut.VDD.value = 1
        dut.VSS.value = 0
    except:
        pass
    
    dut.log.info("Starting firmware loading...")


    
    # Reset regs
    await loader.reset()
    
    # Reset FPGA fabric
    #await loader.fabric_reset() 
    
    await cocotb.triggers.ClockCycles(wb.clk, 10)
    
    # Load FPGA firmware
    await test.wb.write(EFUSE_WTIMER_ADDR, 1)
    await test.wb.write(EFUSE_RTIMER_ADDR, 0x11)
    await loader.load_fw_efuse("firmware.bit")
    dut.io_in.value = 1<<37
    
    await test.wb.read(EFUSE_WTIMER_ADDR)   # hangs until WB is switched back

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
            
