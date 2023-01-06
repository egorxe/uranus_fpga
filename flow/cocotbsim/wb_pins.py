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

UUT_WB_DDR          = 0x30F00000

class WishbonePinsTest:
    def __init__(self, wb):
        self.wb = wb
        self.clk = self.wb.dut.wb_clk_i
                
    # Set out pin value
    async def set_output_pin (self, PN, val):
        await self.wb.write(UUT_WB_DDR + PN, val) 

    async def set_oeb_pin (self, PN, val):
        await self.wb.write(UUT_WB_DDR + PN, val + 0x80000000)     
        
    async def set_irq_pin (self, PN, val):
        await self.wb.write(UUT_WB_DDR + PN, val + 0x40000000)             

    async def get_input_pins(self):
        input_pins = await self.wb.read(UUT_WB_DDR)
        return input_pins

    async def get_input_pins_upper(self):
        input_pins = await self.wb.read(UUT_WB_DDR + 0x8000)
        return input_pins

@cocotb.test()
async def run_test(dut):
    # Create wishbone access helpers
    wb = WishboneRegs(dut, USER_WB_BASEADDR)
    loader = WishboneCfgLoader(wb)
    test = WishbonePinsTest(wb)
    
    io_in = dut.io_in
    io_out = dut.io_out
    io_oeb = dut.io_oeb
    user_irq = dut.user_irq

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
    
    
    dut.log.info("Check if all initial output pins values are correct...")
    
    for i in range(38):
        assert io_oeb[i] == 1
        assert io_out[i] == 1
        
    for i in range(3):
        assert user_irq[i] == 1
        
    dut.log.info("Ok!")

    dut.log.info("Check io_out pins are connected well...")
    
    for i in range(38):
        await test.set_output_pin(i, 0)
        assert io_out[i] == 0
        await loader.wait_for(10)
        await test.set_output_pin(i, 1)
        assert io_out[i] == 1        

    dut.log.info("Ok!")       

    dut.log.info("Check io_oeb pins are connected well...")

    for i in range(38):
        await test.set_oeb_pin(i, 0)
        assert io_oeb[i] == 0
        await test.set_oeb_pin(i, 1)
        assert io_oeb[i] == 1        

    dut.log.info("Ok!")
    
    dut.log.info("Check user_irq pins are connected well...")

    for i in range(3):
        await test.set_irq_pin(i, 0)
        assert user_irq[i] == 0
        await test.set_irq_pin(i, 1)
        assert user_irq[i] == 1        

    dut.log.info("Ok!")       
    
    dut.log.info("Check io_in pins are connected well...")

    for i in range(38):
        io_in[i] = 0
        
    for i in range(32):
        io_in[i] = 1
        buf = await test.get_input_pins()
        assert buf == 2**i
        io_in[i] = 0        

    for i in range(4):
        io_in[i + 32] = 1
        buf = await test.get_input_pins_upper()
        assert buf == 2**i
        io_in[i + 32] = 0  

    dut.log.info("Ok!")   
    
    dut.log.info("Test passed!")       
            
