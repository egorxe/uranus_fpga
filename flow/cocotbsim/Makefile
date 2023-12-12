SIM ?= ghdl

MODULE ?= wishbone_loader_cocotb
TOPLEVEL=ariel_fpga_top
TOPLEVEL_LANG=vhdl
FPGA_LIB = fpgalib
RTL_LIBRARY = $(FPGA_LIB)
BASEDIR ?= $(shell readlink -f ../..)
EXTRA_ARGS = --std=08 -fsynopsys
SIM_ARGS += --wave=wave.ghw --ieee-asserts=disable

EFUSE_HDL_DIR ?= ../../../gf180_efuse_compiler/hdl

VHDL_LIB_ORDER = $(EFUSE_LIB) $(FPGA_LIB) $(RTL_LIBRARY)

EFUSE_SRC = $(EFUSE_HDL_DIR)/*.vhd

VHDL_SOURCES_$(FPGA_LIB) = $(BASEDIR)/rtl/tech/simu_beha_vior/fpga_tech.vhd $(BASEDIR)/rtl/fpga_params_pkg.vhd $(BASEDIR)/rtl/fpga_pkg.vhd $(BASEDIR)/rtl/wishbone_pkg.vhd $(BASEDIR)/rtl/fpga_lut.vhd $(BASEDIR)/rtl/fpga_cfg_shiftreg.vhd $(BASEDIR)/rtl/fpga_logic_cell.vhd $(BASEDIR)/rtl/fpga_routing_mux.vhd $(BASEDIR)/rtl/fpga_logic_block.vhd $(BASEDIR)/rtl/fpga_routing_node.vhd $(BASEDIR)/rtl/fpga_routing_node_wcfg.vhd $(BASEDIR)/rtl/fpga_routing_mux_wcfg.vhd  $(BASEDIR)/rtl/fpga_io_mux.vhd $(BASEDIR)/rtl/fpga_memory_block.vhd $(BASEDIR)/rtl/fpga_struct_block.vhd $(BASEDIR)/rtl/fpga_fabric.vhd $(EFUSE_SRC) $(BASEDIR)/rtl/wb_register32.vhd $(BASEDIR)/rtl/fpga_fw_loader.vhd $(BASEDIR)/rtl/wb_arbiter_sync.vhd $(BASEDIR)/rtl/ariel_fpga_top.vhd 

include $(shell cocotb-config --makefiles)/Makefile.sim

