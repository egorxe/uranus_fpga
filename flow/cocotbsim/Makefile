SIM ?= questa

MODULE ?= wishbone_loader_cocotb
TOPLEVEL=ariel_fpga_top
TOPLEVEL_LANG?=vhdl
FPGA_LIB = fpgalib
#RTL_LIBRARY = worklib

SIMSCRIPT = sim_build/runsim.do

COMPILE_ARGS = -2008 -suppress 1902 -suppress 2892 +define+UNIT_DELAY=\#1 +define+FUNCTIONAL
SIM_ARGS = -t 1ps
COCOTB_HDL_TIMEUNIT = 1ps
COCOTB_HDL_TIMEPRECISION = 1ps

BASEDIR ?= ../..

VHDL_LIB_ORDER = fpgalib
VERILOG_SOURCES = $(BASEDIR)/rtl/tech/asic_skwt_130d/fpga_tech.v $(BASEDIR)/rtl/tech/asic_skwt_130d/models/primitives.v $(BASEDIR)/rtl/tech/asic_skwt_130d/models/sky130_fd_sc_hd.v
VHDL_SOURCES_$(FPGA_LIB) = $(BASEDIR)/rtl/fpga_params_pkg.vhd $(BASEDIR)/rtl/fpga_pkg.vhd $(BASEDIR)/rtl/wishbone_pkg.vhd $(BASEDIR)/rtl/fpga_lut.vhd $(BASEDIR)/rtl/fpga_cfg_shiftreg.vhd $(BASEDIR)/rtl/fpga_logic_cell.vhd $(BASEDIR)/rtl/fpga_routing_mux.vhd $(BASEDIR)/rtl/fpga_logic_block.vhd $(BASEDIR)/rtl/fpga_routing_node.vhd $(BASEDIR)/rtl/fpga_routing_node_wcfg.vhd $(BASEDIR)/rtl/fpga_routing_mux_wcfg.vhd  $(BASEDIR)/rtl/fpga_io_mux.vhd $(BASEDIR)/rtl/fpga_memory_block.vhd $(BASEDIR)/rtl/fpga_struct_block.vhd $(BASEDIR)/rtl/fpga_fabric.vhd
VHDL_SOURCES = $(BASEDIR)/rtl/wb_register32.vhd $(BASEDIR)/rtl/ariel_fpga_top.vhd $(BASEDIR)/rtl/wb_arbiter_sync.vhd

.PHONY: patch-sim
patch-sim: $(SIMSCRIPT)
	# ugly hack to patch name of modelsim library with verilog files
	sed -i 's/vlog -work work/vlog -work $(FPGA_LIB)/g' $(SIMSCRIPT)
	$(MAKE) all

include $(shell cocotb-config --makefiles)/Makefile.sim
