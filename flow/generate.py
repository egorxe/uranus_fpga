#!/usr/bin/env python3

from subprocess import call
import os
import argparse
import random
from params import Params
from utils import *


# Run program & return exitcode
def RunTool(call_args, wdir="", out=""):
    if not wdir:
        wdir = WORK_DIR
    if out:
        f = open(out, "w")
    else:
        f = None
    rc = call(call_args, cwd=wdir, stdout=f)
    if rc != 0:
        exit(rc)

def CheckVPR(log_filename):
    with open(log_filename, 'r') as log:
        for line in log:
            if ("Route failed" in line) or ("Routing failed" in line):
                print("VPR failed, terminating flow")
                exit(-1)

def WriteVsimScript(fd, sources, vsim_args = ""):
    print("vlib fpgalib", file=fd)
    for s in sources:
        ext = os.path.splitext(s)[1]
        if ext == ".vhd":
            print("vcom -2008 -work fpgalib", file=fd, end=' ')
        elif ext == ".v" or ext == ".sv":
            print("vlog -sv -incr -suppress 2892 +define+FUNCTIONAL +define+UNIT_DELAY=#1 -work fpgalib", file=fd, end=' ')
        else:
            raise ValueError("Unknown file extension for simulation!")

        print(AbsPath(s), file=fd)
    print("vsim -t 1ps -voptargs=\"+acc=npr\" " + vsim_args + " fpgalib." + args.sim + " \nrun 100 ms", file=fd)

def WriteYosysScript(fd):
    # print("synth -auto-top -flatten", file=fd)
    # print("abc ", file=fd)

    # general stuff
    print(" read_verilog -lib " + TECHMAP_DIR + "/tech_cells.v", file=fd)
    print(" hierarchy -check -auto-top", file=fd)
    print(" proc\n opt_expr\n opt_clean\n check", file=fd)
    print(" flatten", file=fd)
    print(" opt -full\n wreduce\n alumacc\n share\n opt", file=fd)
    print(" fsm\n opt -fast", file=fd)
    print(" memory -nomap", file=fd)

    # map BRAMs
    print(" memory_bram -rules " + TECHMAP_DIR + "/brams.txt", file=fd)
    print(" techmap -map " + TECHMAP_DIR + "/bram_map.v", file=fd)

    # optimize & map FFs
    print(" opt_clean\n opt -fast -full\n memory_map\n opt -full", file=fd)
    print(" techmap", file=fd)
    # print(" dfflegalize -cell '$_DFF_'", file=fd)
    print(" opt -fast\n abc -fast\n opt -fast", file=fd)
    print(" hierarchy -check\n stat\n check", file=fd)

    # optimize for LUT4 by ABC
    print(" abc -lut 4\n ", file=fd)
    print(" opt_clean -purge\n", file=fd)

    # write netlists
    print(" write_verilog -noexpr " + verilog_netlist, file=fd)
    # print(" write_blif -undef + unconn -attr -cname -param " + blif, file=fd)
    print(" write_blif -undef + unconn " + blif, file=fd)
    print(" stat", file=fd)

# Parse environment
YOSYS_PATH  = AbsPath(LoadEnv("YOSYS_PATH"))
YOSYS       = LoadEnv("YOSYS_BIN", YOSYS_PATH + "/yosys" if YOSYS_PATH else "yosys")
GHDL        = LoadEnv("GHDL_BIN", "ghdl")
YOSYS_WITH_GHDL = LoadEnv("YOSYS_WITH_GHDL", "yosys")
VTR_PATH    = AbsPath(LoadEnv("VTR_PATH"))
VPR         = LoadEnv("VPR_BIN", VTR_PATH + "/vpr/vpr" if VTR_PATH else "vpr")
VSIM        = LoadEnv("VSIM_BIN", "vsim")
BITGEN      = AbsPath(LoadEnv("BITGEN_PY", "./bitgen.py"))
TB_WRAPPER  = AbsPath(LoadEnv("TB_WRAPPER_PY", "./tb_wrapper.py"))
PINOUT2VTR  = AbsPath("./pinout2vtr.py")
PARAMS_PY   = AbsPath(LoadEnv("PARAMS_PY", "./params.py"))
GEN_CFGCON  = AbsPath(LoadEnv("GEN_CFGCON_PY", "./gen_cfg_conn.py"))
WORK_DIR    = AbsPath(LoadEnv("VTR_WORK_DIR", "./work"))
ARCH_DIR    = AbsPath(LoadEnv("ARCH_DIR", "../arch"))
RTL_PATH    = AbsPath(LoadEnv("FPGA_RTL_PATH", "../rtl"))
SIM_PATH    = AbsPath(LoadEnv("FPGA_SIM_PATH", "./sim"))
TECHMAP_DIR = AbsPath(LoadEnv("TECHMAP_DIR", ARCH_DIR + "/yosys"))

SIM_PATH    = AbsPath("./sim")
COCOTB_PATH = AbsPath("./cocotbsim")
COCOTB_BITSTREAM = COCOTB_PATH + "/firmware.bit"

# Parse arguments
parser = argparse.ArgumentParser(description="FPGA synthesys flow with Yosys(GHDL), VPR & bitgen.py")
parser.add_argument("rtl_src", type=str, nargs="+", help="Verilog/VHDL input files")
parser.add_argument("--sdc", type=str, help="Specify timing constraints file for VTR")
parser.add_argument("--tb", type=str, help="If set, testbench wrapper & modelsim script will be generated")
parser.add_argument("--sim", type=str, help="If set, simulator will be launched with supplied entity")
parser.add_argument("--pinout", type=str, help="Specify file with signal to pins mapping")
parser.add_argument("--top", type=str, help="Specify VHDL top unit")
parser.add_argument("--synth", action="store_const", const = True, default = False, help="Run synthesis with Yosys")
parser.add_argument("--pnr", action="store_const", const = True, default = False, help="Run place & route with VPR")
parser.add_argument("--bitgen", action="store_const", const = True, default = False, help="Run bitgen")
parser.add_argument("--gui", action="store_const", const = True, default = False, help="Invoke VPR GUI")
args = parser.parse_args()
# rtl_src = args.verilog
verilog = []
vhdl = []
for s in args.rtl_src:
    if not os.path.isfile(s):
        print("File ", s, " not found!")
        exit(1)
    ext = s.split(".")[-1]
    if ext == "vhd" or ext == "vhdl":
        vhdl.append(AbsPath(s))
    elif ext == "v" or ext == "sv":
        verilog.append(AbsPath(s))
    else:
        print("RTL file ", s, " is of unknown type!")
        exit(1)
if vhdl:
    if not args.top:
        print("Top unit required for VHDL designs!")
        exit(1)
    vhdl2verilog = WORK_DIR + "/" + args.top + "_vhd2v.v"
    verilog.append(vhdl2verilog)
if args.top:
    proj_name = args.top
else:
    proj_name = os.path.basename(os.path.splitext(verilog[0])[0])
basename = AbsPath(WORK_DIR + "/" + proj_name)
blif = basename + ".eblif"
verilog_netlist = basename + "_netlist.v"
arch_params_file = AbsPath(ARCH_DIR + "/params.cfg")
vtr_arch_file = AbsPath(ARCH_DIR + "/vtr/arch.xml")
rtl_params_file = AbsPath(RTL_PATH + "/fpga_params_pkg.vhd")
fpga_txt = AbsPath(SIM_PATH + "/" + proj_name + ".txt")

if (args.synth or args.pnr or args.bitgen) == False:
    # by default run everything
    args.synth = True
    args.pnr = True
    args.bitgen = True

if not os.path.exists(WORK_DIR):
    os.makedirs(WORK_DIR)

# Prepare parameter config files
RunTool([PARAMS_PY, "--cfg", arch_params_file, "--vhd", rtl_params_file, "--vtr", vtr_arch_file])
p = Params(arch_params_file)
RTL_TECH_PATH = RTL_PATH + "/" + TechDir(p)

# Synthesys
if args.synth:
    if vhdl:
        # RunTool([GHDL, "-a", "-fsynopsys", "--std=08"] + vhdl)
        # RunTool([GHDL, "--synth", "--out=verilog", "-fsynopsys", "--std=08", args.top], out=verilog[-1])
        # print("/opt/opencad/bin/yosys -m ghdl -p 'ghdl -fsynopsys --std=08 --work=fpgalib " + srcs + " -e " + vhdl_top +"; hierarchy -check -top " + vhdl_top + "; write_verilog " + OpenlaneDesignsPath(name) + vhdl_top + "_fromvhdl.v'", file=fd)
        RunTool([YOSYS_WITH_GHDL, "-m", "ghdl", "-p", "ghdl -fsynopsys --std=08 " + " ".join(vhdl) + " -e " + args.top + " ; hierarchy -check -top " + args.top + "; write_verilog " + verilog[-1]])
    syn_script_name = WORK_DIR + "/synth.ys"
    with open(syn_script_name, 'w') as syn_script:
        WriteYosysScript(syn_script)
    print("Launching Yosys synthesis tool...")
    RunTool([YOSYS, "-v3", "-l", WORK_DIR + "/yosys.log"] + verilog + [syn_script_name])

# Produce pinout
fix_pins = []
pad_file = basename + ".pad"
if args.pinout:
    RunTool([PINOUT2VTR, AbsPath(args.pinout), pad_file, "--params", arch_params_file])
    fix_pins = ["--fix_pins", AbsPath(pad_file)]

# Generate testbench
if args.tb:
    if not os.path.isfile(args.tb):
        print("Designated testbench file " + args.tb + " not found!")
        exit(1)
    tb_wrapper_file = basename + "_fpga_wrapper.vhd"
    if not os.path.exists(SIM_PATH):
        os.makedirs(SIM_PATH)
    tb_loader_wrapper_file = basename + "_fpgaloader_wrapper.vhd"
    vsim_script_fpga = SIM_PATH + "/" + proj_name + "_fpga_vsim.tcl"
    vsim_script_behav = SIM_PATH + "/" + proj_name + "_behav_vsim.tcl"
    vsim_script_netlist = SIM_PATH + "/" + proj_name + "_netlist_vsim.tcl"
    vsim_script_loader = SIM_PATH + "/" + proj_name + "_loader_vsim.tcl"
    vsim_script_sdf = SIM_PATH + "/" + proj_name + "_sdf_vsim.tcl"
    print("Launching testbench wrapper generator...")
    RunTool([TB_WRAPPER, arch_params_file, proj_name, verilog_netlist, pad_file, tb_wrapper_file, tb_loader_wrapper_file])
    if args.sim:
        common_src = PrependPaths(p.src.SRC_LIST_COMMON, RTL_PATH)
        WriteVsimScript(open(vsim_script_fpga, "w"), PrependPaths(p.src.SRC_LIST_TECH_FPGA + p.tech_config.TECH_MODELS_LIST, RTL_TECH_PATH) +
            PrependPaths(p.src.SRC_LIST_FPGA+p.src.SRC_LIST_FPGATB, RTL_PATH) + [tb_wrapper_file] + [args.tb])
        WriteVsimScript(open(vsim_script_behav, "w"), verilog + [args.tb])
        WriteVsimScript(open(vsim_script_netlist, "w"), [YOSYS_PATH + "/techlibs/common/simlib.v", YOSYS_PATH + "/techlibs/common/simcells.v"] + [verilog_netlist] + [args.tb])
        WriteVsimScript(open(vsim_script_loader, "w"), common_src + PrependPaths(p.src.SRC_LIST_TECH_FPGA + p.tech_config.TECH_MODELS_LIST, RTL_TECH_PATH) +
            PrependPaths(p.src.SRC_LIST_FPGALOADER+p.src.SRC_LIST_FPGATB, RTL_PATH) + [tb_loader_wrapper_file] + [args.tb])
        # WriteVsimScript(open(vsim_script_sdf, "w"), FPGASDF_SRC_LIST + [tb_loader_wrapper_file] + [args.tb], "-sdfnoerror")
    fix_pins = ["--fix_pins", AbsPath(pad_file)]

# Place & route
if args.pnr:
    vpr_args = [VPR, vtr_arch_file, basename, "--circuit_file", blif, "--route_chan_width", str(p.TOTAL_TRACKS), "--max_router_iterations", "10000",
        "--constant_net_method", "route", "--echo_file", "on", "--gen_post_synthesis_netlist", "on", "--initial_pres_fac", "0.1", "--pres_fac_mult", "1.1",
        "--first_iter_pres_fac", "0.00", "--min_incremental_reroute_fanout", "400", "--astar_fac", "1.8", "--max_criticality", "0.5", 
        "--routing_failure_predictor", "off", "--bb_factor", "30", "--seed", str(random.randrange(100000)), "--congested_routing_iteration_threshold", "0.25", 
        "--criticality_exp", "0.0", "--place_algorithm", "path_timing_driven", "--timing_tradeoff", "0.1", "--router_init_wirelength_abort_threshold", "0.95"]
    if fix_pins:
        vpr_args += fix_pins

    if args.sdc:
        vpr_args += ["--sdc_file", AbsPath(args.sdc)]
    if args.gui:
        vpr_args += ["--disp", "on"]
    print("Launching VPR...")
    RunTool(vpr_args)
    CheckVPR(WORK_DIR + "/vpr_stdout.log")

# Bitgen
if args.bitgen:
    os.system("mkdir -p " + SIM_PATH + " " + COCOTB_PATH)
    RunTool([BITGEN, arch_params_file, basename, fpga_txt])
    os.system("cp " + fpga_txt + ".bit " + COCOTB_BITSTREAM)

# Simulate
if args.sim:
    print("Launching Modelsim...")
    RunTool([VSIM, "-do", vsim_script_loader], SIM_PATH)
