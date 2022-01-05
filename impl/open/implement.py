#!/usr/bin/env python3

import argparse
import glob
from params import Params
from utils import *


########################################################################################################################
################################################### OPENLANE HELPERS ###################################################
########################################################################################################################

RTL_PATH    = AbsPath(LoadEnv("FPGA_RTL_PATH", "../../rtl"))
OPENLANE_PATH = AbsPath(LoadEnv("HOME", "proj/OpenLane"))
OPENLANE_DESIGNS_PATH = "designs"
ADD_CONFIG_TCL = "_ADD_CONFIG_TCL"

def OpenlaneDesignsPath(name):
    return OPENLANE_DESIGNS_PATH + "/" + name + "/"

def OpenlanePinCfg(pins, side):
    if side == "top":
        side = "N"
    elif side == "bottom":
        side = "S"
    elif side == "left":
        side = "W"
    elif side == "right":
        side = "E"
        
    res = "#" + side + "\n"
    
    pins = pins.replace("[", "\[") 
    pins = pins.replace("]", "\]")
    for p in pins.split():
        res += p + "\n"
    res  += "\n"
    
    return res
   
# Generate Openlane start script including VHDL-to-Verilog by GHDL
def WriteOpenlaneScript(name, src_list, tech_src_list, vhdl_top=""):
    if not vhdl_top:
        vhdl_top = name
    sname = name + ".openlane.sh"
    fd = open(sname, "w")
    dp = OpenlaneDesignsPath(name)
    
    srcs=""
    for src in src_list:
        srcs += src + " "
    tech_srcs=""
    for src in tech_src_list:
        tech_srcs += src + " "
    
    print("#!/bin/sh", file=fd)
    print("set -e\nrm -f fpgalib-*.cf ", file=fd)
    print("/opt/opencad/bin/yosys -m ghdl -p 'ghdl -fsynopsys --std=08 --work=fpgalib " + srcs + " -e " + vhdl_top +"; hierarchy -check -top " + vhdl_top + "; write_verilog " + OpenlaneDesignsPath(name) + vhdl_top + "_fromvhdl.v'", file=fd)
    if tech_srcs:
        print("cp " + tech_srcs + " " + dp, file=fd)
    print("$OPENLANE_PATH/flow.tcl -design " + dp, file=fd)
    print("exit $? ", file=fd)

    fd.close()
    os.chmod(sname, 0o755)

# Generate Openlane design        
def WriteOpenlaneDesign(name, src_list, tech_src_list, env_vars, pin_cfg, macro_cfg="", vhdl_top=""):
    design_path = OPENLANE_DESIGNS_PATH + "/" + name
    os.makedirs(design_path, exist_ok=True)
    dp = OpenlaneDesignsPath(name)
    if not vhdl_top:
        vhdl_top = name
    
    # write pin config file
    fd = open(dp + "pin.cfg", "w")
    print(pin_cfg, file=fd)
    
    # write macro config if present
    if macro_cfg:
        macro_file = dp + "macro.cfg"
        with open(macro_file,"w") as fd:
            print(macro_cfg, file=fd)
        env_vars["MACRO_PLACEMENT_CFG"] = '"'+macro_file+'"'
    
    # generate openlane config  
    env_vars["DESIGN_NAME"] = name
    verilogs = dp + vhdl_top + "_fromvhdl.v"
    if tech_src_list:
        for t in tech_src_list:
            verilogs += " " + dp + t.split("/")[-1]  # !
    env_vars["VERILOG_FILES"] = '"' +  verilogs + '"'
    env_vars["BASE_SDC_FILE"] = '"' + dp + name + '.sdc"'
    env_vars["FP_PIN_ORDER_CFG"] = '"' + dp + 'pin.cfg"'

    env_vars["SYNTH_DRIVING_CELL"] = '"sky130_fd_sc_hd__buf_1"'
    env_vars["SYNTH_DRIVING_CELL_PIN"] = '"X"'
    
    env_vars["ROUTING_CORES"] = 10
    
    env_vars_text = ""
    if ADD_CONFIG_TCL in env_vars:
        env_vars_text += env_vars[ADD_CONFIG_TCL] + "\n"
        del env_vars[ADD_CONFIG_TCL]
    
    for e in env_vars:
        env_vars_text += OPENLANE_CFG_TEMPLATE.format(NAME=e, VAL=env_vars[e])
     
    fd = open(design_path + "/config.tcl", "w")
    print(env_vars_text, file=fd)
    
    WriteOpenlaneScript(name, src_list, tech_src_list, vhdl_top)


########################################################################################################################
####################################################   SDC HELPERS  ####################################################
########################################################################################################################

# Generate SDC
def SDCInputDelay(delay, clock, ports):
    return "set_input_delay {DELAY}  -clock [get_clocks {CLOCK}] [get_ports {PORTS}]\n".format(DELAY=(delay/1000), CLOCK=clock, PORTS=ports)   # ps to ns
    
def SDCMaxDelay(delay_from, delay_to, val):
    return "set_max_delay -ignore_clock_latency {VAL} -from {FROM} -to {TO}\n".format(VAL=(val/1000), FROM=delay_from, TO=delay_to)   # ps to ns

def SDCDisableTiming(from_pin):
    return "set_disable_timing {PIN}\n".format(PIN=from_pin)

def SDCFalsePath(pfrom="", pto="", through=""):
    s = "set_false_path "
    if pfrom:
        s += "-from " + pfrom + " "
    if pto:
        s += "-to " + pto + " "
    if through:
        s += "-through [get_pins " + through + "]"
    return s

def SDCAddClock(add_clock):
    if '/' in add_clock[0]:
        name = add_clock[0].split('/')[0]
        getter = 'get_pins'
    else:
        name = add_clock[0]
        getter = 'get_ports'
    return (('create_clock -name "{CLK_NAME}" -add -period {PERIOD} [{GETTER} {PIN}]').format(CLK_NAME=name, PIN=add_clock[0], GETTER=getter, PERIOD=add_clock[1]), name) 

def WriteSDC(name, add_sdc, add_clock = []):
    fd = open(OpenlaneDesignsPath(name) + name + ".sdc", "w")
    clock_names = []
    
    for clk in add_clock:
        clk = SDCAddClock(clk)
        clock_names.append(clk[1])
        print(clk[0], file=fd)
    print(SDC_TEMPLATE, file=fd)
    
    print("# Disable all cross-clocking paths", file=fd)
    for sc in clock_names:
        for dc in clock_names:
            if sc != dc:
                print(SDCFalsePath(pfrom="[get_clocks "+sc+"]", pto="[get_clocks "+dc+"]"), file=fd)

    print(add_sdc, file=fd)
    fd.close()


########################################################################################################################
###################################################     FPGA TOP     #####################################################
########################################################################################################################

TOP_LEVEL = "user_project_wrapper"

LB_TEMPLATE = "ariel_fpga_top_inst.fpga_fabric_inst.struct_blocks_x:{X}.struct_blocks_y:{Y}.struct_block"
RNODE_TEMPLATE = "ariel_fpga_top_inst.fpga_fabric_inst.{O}_routing_network_x:{X}.{O}_routing_network_y:{Y}.routing_node_{D}" 

RNODE_IN_TEMPLATE   = RNODE_TEMPLATE + ".node.muxes:{T}.bufs:{I}.rnode_in.tech_buf/$BUFIPIN" 
RNODE_OUTI_TEMPLATE = RNODE_TEMPLATE + ".node.muxes:{T}.rnode_tfinish.tech_buf/$BUFOPIN"
RNODE_OUT_TEMPLATE  = RNODE_TEMPLATE + ".node.muxes:{T}.rnode_tstart.tech_buf/$BUFIPIN"

NODES = [("up", [(0, 1, "up"), (1, 0, "right"), (0, 0, "left")]), 
    ("right", [(1, 0, "right"), (0, 0, "down"), (0, 1, "up")]),
    ("down", [(0, -1, "down"), (0, -1, "left"), (1, -1, "right")]),
    ("left", [(-1, 0, "left"), (-1, 1, "up"), (-1, 0, "down")])]

# Helpers for fabric SDC 
def RNodeOrient(direction):
    # orientation from direction
    if (direction == "up") or (direction == "down"):
        return "vertical"
    else:
        return "horizontal"
        
def HasRNode(direction, x, y):
    # determine if routing node is present
    orient = RNodeOrient(direction)
    if orient == "vertical" and (x >= 0 and y > 0 and x < p.FPGA_FABRIC_SIZE_X-1 and y < p.FPGA_FABRIC_SIZE_Y-1):
        return True
    elif orient == "horizontal" and (x > 0 and y >= 0 and x < p.FPGA_FABRIC_SIZE_X-1 and y < p.FPGA_FABRIC_SIZE_Y-1):
        return True
    return False

def GHDLRnodeCoord(o, x, y):
    # ugly hack, cause GHDL always numbers for-generated stuff from 1
    if RNodeOrient(o) == "vertical":
        x +=1
    else:
        y += 1
    return (x,y)

# Complete FPGA fabric SDC generator
def FabricSDC():
    lb_offsets = [(0, 0, "up"), (-1, 0, "up"), (0, 0, "right"), (0, -1, "right"), 
        (0, 0, "down"), (-1, 0, "down"), (0, 0, "left"), (0, -1, "left")]

    add_sdc = SDC_BUFPIN_TEMPLATE
    
    add_sdc += SDCDisableTiming("[get_cells *loop_breaker*]")
    
    # Routing node <-> LB constraints
    add_sdc += "\n# Routing node <-> LB constraints\n"
    for x in range(1, p.FABRIC_BLOCKS_X+1):
        for y in range(1, p.FABRIC_BLOCKS_Y+1):
            for o in lb_offsets:
                node_x = x + o[0]
                node_y = y + o[1]
                if HasRNode(o[2], node_x, node_y):
                    rcoord = GHDLRnodeCoord(o[2], node_x, y+o[1])
                    add_sdc += SDCMaxDelay(("[get_pins "+RNODE_OUT_TEMPLATE+"]").format(X=rcoord[0], Y=rcoord[1], O=RNodeOrient(o[2]), D=o[2], T="*"),
                        ("[get_pins "+LB_TEMPLATE+"/input*_i]").format(X=x, Y=y), p.tech_config.TECH_BINPUT_DELAY)
                    add_sdc += SDCMaxDelay(("[get_pins "+LB_TEMPLATE+"/outputs_o*]").format(X=x, Y=y),
                        ("[get_pins "+RNODE_IN_TEMPLATE+"]").format(X=rcoord[0], Y=rcoord[1], O=RNodeOrient(o[2]), D=o[2], T="*", I="*"), p.tech_config.TECH_BOUTPUT_DELAY)

    # Routing node <-> routing node constraints
    add_sdc += "\n# Routing node internal && RN <-> RN constraints\n"
    for x in range(0, p.FPGA_FABRIC_SIZE_X):
        for y in range(0, p.FPGA_FABRIC_SIZE_Y):
            for n in NODES:
                if HasRNode(n[0], x, y):
                    rcoord = GHDLRnodeCoord(n[0], x, y)
                    # internal
                    add_sdc += SDCMaxDelay(("[get_pins "+RNODE_IN_TEMPLATE+"]").format(X=rcoord[0], Y=rcoord[1], O=RNodeOrient(n[0]), D=n[0], T="*", I="*"),
                        ("[get_pins "+RNODE_OUTI_TEMPLATE+"]").format(X=rcoord[0], Y=rcoord[1], O=RNodeOrient(n[0]), D=n[0], T="*"), p.tech_config.TECH_RNODE_DELAY)
                    # add_sdc += SDCMaxDelay("[get_pins *loop_breaker*.tech_buf*/$BUFOPIN]", "[get_ports route_o*]", p.tech_config.TECH_ROUTE_DELAY)
                    
                    # neibhour RNs
                    for o in n[1]:
                        node_x = x + o[0]
                        node_y = y + o[1]
                        if HasRNode(o[2], node_x, node_y):
                            rcoord2 = GHDLRnodeCoord(o[2], node_x, y+o[1])
                            add_sdc += SDCMaxDelay(("[get_pins "+RNODE_OUT_TEMPLATE+"]").format(X=rcoord[0], Y=rcoord[1], O=RNodeOrient(n[0]), D=n[0], T="*"),
                                ("[get_pins "+RNODE_IN_TEMPLATE+"]").format(X=rcoord2[0], Y=rcoord2[1], O=RNodeOrient(o[2]), D=o[2], T="*", I="*"), p.tech_config.TECH_RSEGM_DELAY)

    # From IO to routing nodes constraints
    io_nodes = ((1, "*"), (p.FPGA_FABRIC_SIZE_X-1, "*"), ("*", 1), ("*", p.FPGA_FABRIC_SIZE_Y-1))   # in GHDL numbering!
    add_sdc += "\n# From IO to routing nodes constraints\n"
    for n in io_nodes:
        add_sdc += SDCMaxDelay("[get_ports io_in*]", ("[get_pins "+RNODE_IN_TEMPLATE+"]").format(X=n[0], Y=n[1], O="*", D="*", T="*", I="*"), p.tech_config.TECH_IOIN_DELAY)
        # add_sdc += SDCMaxDelay("[get_clocks wb_clk_i]", ("[get_pins "+RNODE_IN_TEMPLATE+"]").format(X=n[0], Y=n[1], O="*", D="*", T="*", I="*"), p.tech_config.TECH_IOIN_DELAY)
        add_sdc += SDCMaxDelay(("[get_pins "+RNODE_OUT_TEMPLATE+"]").format(X=n[0], Y=n[1], O="*", D="*", T="*"), "[get_ports io_out*]", p.tech_config.TECH_IOOUT_DELAY)
        # add_sdc += SDCMaxDelay(("[get_pins "+RNODE_OUT_TEMPLATE+"]").format(X=n[0], Y=n[1], O="*", D="*", T="*"), "[get_clocks wb_clk_i]", p.tech_config.TECH_IOOUT_DELAY)
        
    # Wishbone bus
    add_sdc += "set_input_delay 0 -clock [get_clocks wb_clk_i] [get_ports wbs*_i]"

    WriteSDC(TOP_LEVEL, add_sdc, [LOGIC_CLOCK, BLOCK_CFG_CLOCK, VRNODE_CFG_CLOCK, HRNODE_CFG_CLOCK])
    # WriteSDC(TOP_LEVEL, add_sdc, [LOGIC_CLOCK])

def GetPinNets(clk):
    return "{get_full_name \[get_nets -of_objects "+ clk[0] +"\]} "

# Macro placement helpers
def PlaceMacro(name, x, y):
    return name + " " + str(x) + " " + str(y) + " N\n"

LB_OFFSET_X = 120    
LB_OFFSET_Y = 240     
LB_SIZE   = 200    
LB_STEP   = LB_SIZE*1.4
LB_STEP_Y  = LB_SIZE*1.5
    
def PlaceFabricMacros():
    pl = ""
    for x in range(1, p.FABRIC_BLOCKS_X+1):
        for y in range(1, p.FABRIC_BLOCKS_Y+1):
            pl += PlaceMacro(LB_TEMPLATE.format(X=x, Y=y), (x-1)*LB_STEP+LB_OFFSET_X, (y-1)*LB_STEP_Y+LB_OFFSET_Y)
       
    return pl

def FabricOpenlane(partitions):
    pins_cfg = open("caravel_user_pin_order.cfg").read()
    macro_cfg = PlaceFabricMacros()

    clock_nets  = GetPinNets(BLOCK_CFG_CLOCK)
    clock_nets += GetPinNets(VRNODE_CFG_CLOCK)
    clock_nets += GetPinNets(HRNODE_CFG_CLOCK)
    
    ol_vars = {
        ADD_CONFIG_TCL : "source $::env(CARAVEL_ROOT)/openlane/user_project_wrapper/fixed_wrapper_cfgs.tcl",
        "DESIGN_IS_CORE" : 1,
        
        "SYNTH_STRATEGY" : '"AREA 0"',
        
        "FP_PDN_CORE_RING" : 1,
        "FP_PDN_CHECK_NODES" : 0,
        
        "CLOCK_PERIOD" : 100,
        "CLOCK_PORT" : '"wb_clk_i"',
        "CLOCK_NET" : '"wb_clk_i"',
        "CLOCK_NETS_EVAL" : '"' + clock_nets + '"',
        "PL_MAX_DISPLACEMENT_X" : 3000,
        "PL_MAX_DISPLACEMENT_Y" : 1000,
        
        "FP_PDN_VOFFSET" : 40,
        "FP_PDN_HOFFSET" : 40,
        "FP_PDN_VPITCH" : LB_STEP/4,
        "FP_PDN_HPITCH" : LB_STEP_Y/8,
        "FP_PDN_AUTO_ADJUST" : 0,
        "FP_PDN_IRDROP" : 0,
        
        "PL_TIME_DRIVEN" : 1,
        "PL_TARGET_DENSITY" : 0.30,
        "DIODE_INSERTION_STRATEGY" : 0,
        
        # to meet li1 density
        "FP_HORIZONTAL_HALO" : 20,
        "FP_VERTICAL_HALO" : 40,
        
        "PL_RESIZER_MAX_WIRE_LENGTH" : 2000.0,
        "PL_RESIZER_ALLOW_SETUP_VIOS" : 1,
        "PL_RESIZER_HOLD_SLACK_MARGIN" : 0.3,
        "PL_RESIZER_MAX_SLEW_MARGIN" : 10,
        "GLB_RESIZER_MAX_SLEW_MARGIN" : 10,
        "GLB_RESIZER_HOLD_SLACK_MARGIN" : 0.2,
        "GLB_RESIZER_ALLOW_SETUP_VIOS" : 1,
        "GLB_RESIZER_TIMING_OPTIMIZATIONS" : 1,
        
        "GLB_RT_ADJUSTMENT" : 0.1,
        "GLB_RT_L2_ADJUSTMENT" : 0.9,
        "GLB_RT_L3_ADJUSTMENT" : 0.7,
        
        "FP_PDN_MACRO_HOOKS" : '"' + LB_DESIGN_NAME + ' vccd1 vssd1"',
        
        # use custom PDN config to skip stripes generation for unused domains
        "PDN_NO_STRIPE_DOMAINS" : '[list {vccd2} {vdda1} {vdda2}]',
        "PDN_CFG" : '"'+AbsPath('.')+'/pdn_cfg.tcl"',
        
        "VERILOG_FILES_BLACKBOX" : '"'+AbsPath('.')+'/macros.v"',
        "EXTRA_LEFS" : '"'+AbsPath('.')+'/best/{LB}/results/finishing/{LB}.lef"'.format(LB=LB_DESIGN_NAME),
        "EXTRA_GDS_FILES" : '"'+AbsPath('.')+'/best/{LB}/results/finishing/{LB}.gds"'.format(LB=LB_DESIGN_NAME)
    }
    RTL_TECH_PATH = RTL_PATH + "/" + TechDir(p)
    WriteOpenlaneDesign(TOP_LEVEL, PrependPaths(p.src.SRC_LIST_ARIEL, RTL_PATH), PrependPaths(p.src.SRC_LIST_TECH_ARIEL, RTL_TECH_PATH), ol_vars, pins_cfg, macro_cfg, "ariel_fpga_top")
    

########################################################################################################################
####################################################  STRUCT BLOCK  ####################################################
########################################################################################################################

LB_DESIGN_NAME = "fpga_struct_block"

LOGIC_CELL_TEMPLATE = "*logic_block*logic_cells*{i}*cell"

LOOPBREAKER_TEMPLATE = LOGIC_CELL_TEMPLATE + ".lut.breaker*loop_breaker.tech_buf"
LOOPBREAKER_IN_TEMPLATE = LOOPBREAKER_TEMPLATE + "/$BUFIPIN"
LOOPBREAKER_OUT_TEMPLATE = LOOPBREAKER_TEMPLATE + "/$BUFOPIN"

LUTBUF_IN_TEMPLATE = LOGIC_CELL_TEMPLATE + ".lut.breaker*lut_tfinish.tech_buf/$BUFIPIN"
LUTBUF_OUT_TEMPLATE = LOGIC_CELL_TEMPLATE + ".lut.breaker*lut_tstart.tech_buf/$BUFOPIN"

CELL_IN_TEMPLATE = LOGIC_CELL_TEMPLATE + ".in_bufs*{j}*cell_tstart.tech_buf/$BUFOPIN"

CELLREGISTER_TEMPLATE = LOGIC_CELL_TEMPLATE + ".cell_reg.register"
CELLREGISTER_D_TEMPLATE = CELLREGISTER_TEMPLATE + "/D"
CELLREGISTER_Q_TEMPLATE = CELLREGISTER_TEMPLATE + "/Q"

def SpreadBlockPins():
    sides = ["up", "right", "down", "left"]
    pins = ["config_ena_i config_shift_i", "", "config_shift_o", ""]

    for n in range(0, p.BLOCK_OUTPUTS, 4):
        for s in range(4):
            pins[s] += " {NAME}[{n}]".format(NAME="outputs_o", n=n+s)
    
    for s in range(4):
        for t in range(p.TOTAL_TRACKS):
            pins[s] += " inputs_{SIDE}_i[{n}]".format(SIDE=sides[s], n=t)
            
    res  = OpenlanePinCfg(pins[0], "top")
    res += OpenlanePinCfg(pins[1], "right")
    res += OpenlanePinCfg(pins[2], "bottom")
    res += OpenlanePinCfg(pins[3], "left")
    return res

def LogicBlockSDC():
    add_sdc = SDC_BUFPIN_TEMPLATE

    # Generate logic cell constraints
    add_sdc += "\n# Logic cell constraints\n"
    add_sdc += SDCDisableTiming(("[get_cells " + LOOPBREAKER_TEMPLATE + "]").format(i="*")) + "\n" # ! in OR breaks also paths terminated at this cell !
    
    for i in range(p.CELLS_PER_BLOCK):
        for j in range(p.FPGA_LUT_WIDTH):
            lut_delay = p.tech_config.TECH_LUT_DELAY
            if j >=2:
                lut_delay *= 2
            add_sdc += SDCMaxDelay(("[get_pins "+CELL_IN_TEMPLATE+"]").format(i=i+1, j=j+1),
                ("[get_pins "+LUTBUF_IN_TEMPLATE+"]").format(i=i+1), lut_delay)
        add_sdc += SDCMaxDelay(("[get_pins " + LUTBUF_OUT_TEMPLATE + "]").format(i=i+1),
            ("[get_pins " + CELLREGISTER_D_TEMPLATE + "]").format(i=i+1), p.tech_config.TECH_ROUTE_DELAY*2+p.tech_config.TECH_REG_SETUP)

    # Generate crossbar constraints
    add_sdc += "\n# Crossbar constraints\n"
    add_sdc += SDCMaxDelay(("[get_pins "+LUTBUF_OUT_TEMPLATE+"]").format(i="*"),
        ("[get_pins "+CELL_IN_TEMPLATE+"]").format(i="*", j="*"), p.tech_config.TECH_LBCROSS_DELAY)
    add_sdc += SDCMaxDelay("[get_ports inputs_i*]", ("[get_pins "+CELL_IN_TEMPLATE+"]").format(i="*", j="*"), p.tech_config.TECH_LBCROSS_DELAY)

    # Generate output constraints
    add_sdc += "\n# Output constraints\n"
    for i in range(p.CELLS_PER_BLOCK):
        add_sdc += SDCMaxDelay(("[get_pins " + LUTBUF_OUT_TEMPLATE + "]").format(i=i+1), "[get_ports outputs_o[{i}]]".format(i=i), p.tech_config.TECH_LBOUT_DELAY)
        add_sdc += SDCMaxDelay(("[get_pins " + CELLREGISTER_Q_TEMPLATE + "]").format(i=i+1), "[get_ports outputs_o[{i}]]".format(i=i), p.tech_config.TECH_LBOUT_DELAY)

    # Generate config input constraints
    add_sdc += SDCInputDelay(0, CONFIG_CLOCK[0], "config_shift_i")
    
    WriteSDC(LB_DESIGN_NAME, add_sdc, [LOGIC_CLOCK, CONFIG_CLOCK])

def LogicBlockOpenlane():
    pin_cfg = SpreadBlockPins()
    ol_vars = {
            "DESIGN_IS_CORE" : 0,
            "SYNTH_STRATEGY" : '"AREA 2"',
            "CLOCK_PERIOD" : 100,
            "CLOCK_PORT" : '"clk_i config_clk_i"',
            "FP_CORE_UTIL" : 40,
            
            "FP_SIZING"  : '"absolute"',
            "DIE_AREA"  : '"0 0 180 180"',
            
            
            "PL_TARGET_DENSITY" : 0.65,
            "SYNTH_TIMING_DERATE" : 0.07,
            "PL_TIME_DRIVEN" : 1,
            "GLB_RT_MAXLAYER" : 5,
            "VDD_NETS" : "[list {vccd1}]",
            "GND_NETS" : "[list {vssd1}]",
            "FP_PDN_VPITCH" : 50,
            "FP_PDN_AUTO_ADJUST" : 0,
            
            "GLB_RESIZER_TIMING_OPTIMIZATIONS" : 0,
            "GLB_RT_ALLOW_CONGESTION" : 1,
            "DIODE_INSERTION_STRATEGY" : 0,
            
            # "RIGHT_MARGIN_MULT" : 2,
            # "LEFT_MARGIN_MULT" : 2,
            # "TOP_MARGIN_MULT" : 2,
            # "BOTTOM_MARGIN_MULT" : 2
        }
    RTL_TECH_PATH = RTL_PATH + "/" + TechDir(p)
    WriteOpenlaneDesign(LB_DESIGN_NAME, PrependPaths(p.src.SRC_LIST_LB, RTL_PATH), PrependPaths(p.src.SRC_LIST_TECH_LB, RTL_TECH_PATH), ol_vars, pin_cfg)
    
    
########################################################################################################################
####################################################      MAIN      ####################################################
########################################################################################################################

def Main():
    # Generate synthesis & implementation scripts for logic block
    LogicBlockOpenlane()
    LogicBlockSDC()
    
    # # Generate synthesis & implementation scripts for FPGA fabric
    FabricOpenlane(["fpga_struct_block", "fpga_routing_node_wcfg"])
    FabricSDC()


########################################################################################################################
####################################################   TEMPLATES    ####################################################
########################################################################################################################

# Templates
DESIGN_NAME_TEMPLATE            = "designs/{NAME}"
DESIGN_NAME_TEMPLATE_OPENROAD   = DESIGN_NAME_TEMPLATE + "_openroad"
LEF_NAME_TEMPLATE               = DESIGN_NAME_TEMPLATE_OPENROAD + "/{NAME}.lef"
LIB_NAME_TEMPLATE               = DESIGN_NAME_TEMPLATE_OPENROAD + "/{NAME}.lib"

SDC_TEMPLATE = r'''
set_units -time 1ns

#set input_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_PCT)]
#set output_delay_value [expr $::env(CLOCK_PERIOD) * $::env(IO_PCT)]
#puts "\[INFO\]: Setting output delay to: $output_delay_value"
#puts "\[INFO\]: Setting input delay to: $input_delay_value"

set_max_fanout $::env(SYNTH_MAX_FANOUT) [current_design]

if {[info exists CLOCK_PORT]} {
    set clk_indx [lsearch [all_inputs] [get_port $::env(CLOCK_PORT)]]
    #set rst_indx [lsearch [all_inputs] [get_port resetn]]
    set all_inputs_wo_clk [lreplace [all_inputs] $clk_indx $clk_indx]
    #set all_inputs_wo_clk_rst [lreplace $all_inputs_wo_clk $rst_indx $rst_indx]
    set all_inputs_wo_clk_rst $all_inputs_wo_clk
    puts "\[INFO\]: Setting clock uncertainity to: $::env(SYNTH_CLOCK_UNCERTAINITY)"
    set_clock_uncertainty $::env(SYNTH_CLOCK_UNCERTAINITY) [get_clocks $::env(CLOCK_PORT)]
}

# TODO set this as parameter
set_driving_cell -lib_cell $::env(SYNTH_DRIVING_CELL) -pin $::env(SYNTH_DRIVING_CELL_PIN) [all_inputs]
set cap_load [expr $::env(SYNTH_CAP_LOAD) / 1000.0]
puts "\[INFO\]: Setting load to: $cap_load"
set_load  $cap_load [all_outputs]

puts "\[INFO\]: Setting clock transition to: $::env(SYNTH_CLOCK_TRANSITION)"
#set_clock_transition $::env(SYNTH_CLOCK_TRANSITION) [get_clocks $::env(CLOCK_PORT)]

puts "\[INFO\]: Setting timing derate to: [expr {$::env(SYNTH_TIMING_DERATE) * 10}] %"
set_timing_derate -early [expr {1-$::env(SYNTH_TIMING_DERATE)}]
set_timing_derate -late [expr {1+$::env(SYNTH_TIMING_DERATE)}]

'''

SDC_BUFPIN_TEMPLATE = r'''
set BUFIPIN [lindex [lreverse [split [lindex [get_name [lindex [get_pin -hier *tech_buf/*] 0]] 0] /]] 0]
set BUFOPIN [lindex [lreverse [split [lindex [get_name [lindex [get_pin -hier *tech_buf/*] 1]] 0] /]] 0]
'''

OPENLANE_CFG_TEMPLATE = r'''set ::env({NAME}) {VAL}
'''

# Parse arguments
parser = argparse.ArgumentParser(description="Helper to generate FPGA implementation scripts for Cadence tools")
parser.add_argument("--cfg", type=str, help="Input parameters cfg file", default="../../arch/params.cfg")
args = parser.parse_args()
p = Params(args.cfg)

# Misc defines
CONFIG_CLOCK    = ("config_clk_i", 1000)
BLOCK_CFG_CLOCK = ("ariel_fpga_top_inst.config_block_clk_buf.tech_clkbuf/X", 1000)
VRNODE_CFG_CLOCK= ("ariel_fpga_top_inst.config_vrnode_clk_buf.tech_clkbuf/X", 1000)
HRNODE_CFG_CLOCK= ("ariel_fpga_top_inst.config_hrnode_clk_buf.tech_clkbuf/X", 1000)
LOGIC_CLOCK     = ("wb_clk_i", 40)
NETLIST_NAME    = "netlist_{X}x{Y}_{TECH}".format(X=p.FPGA_FABRIC_SIZE_X, Y=p.FPGA_FABRIC_SIZE_Y, TECH=p.TARGET_TECHNOLOGY.lower()[5:9])
TECH_DIR        = "../tech/"+p.TARGET_TECHNOLOGY.lower()

# Call main
Main()
