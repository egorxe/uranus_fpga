import cocotb
from cocotb.triggers import RisingEdge
from cocotb.clock import Clock
from cocotbext.wishbone.driver import WishboneMaster
from cocotbext.wishbone.driver import WBOp

from wishbone_loader_cocotb import *

USER_WB_BASEADDR    = 0x30F00000

BLOCK_CFG_ADDR      = 0x30100000
VRNODE_CFG_ADDR     = 0x30200000
HRNODE_CFG_ADDR     = 0x30300000
CLK_CFG_ADDR        = 0x30E00000
RST_CFG_ADDR        = 0x30A00000

KEY0_ADDR           = 0x30F00000
KEY1_ADDR           = 0x30F00004
DATA_ADDR           = 0x30F00008

FPGA = 1

@cocotb.test()
async def run_test(dut):
    # Create wishbone access helpers
    wb = WishboneRegs(dut, USER_WB_BASEADDR)
    loader = WishboneCfgLoader(wb)

    if FPGA:
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
        
    else:
        # behav sim
        dut.log.info("Resetting WB...")
        await loader.reset()
    
    dut.log.info("Design ready for test!")
    
    dut.log.info("Loading keys...")
    await wb.write(KEY0_ADDR, 0x01234567)
    await wb.write(KEY1_ADDR, 0x89ABCDEF)
    
    dut.log.info("Loading data & starting encrypt...")
    cur_cnt = await wb.write(DATA_ADDR, 0xDEADBEEF)
    await loader.wait_for(50)

    dut.log.info("Checking encrypted data...")
    # ~ result = await wb.read(DATA_ADDR)
    result = dut.io_out.value & 0xFFFFFFFF
    dut.log.info("Encrypted: ", hex(result))
    
    # check result
    assert (result == 0x919cdecf)
    dut.log.info("Ok")      
            
