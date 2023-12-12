#!/usr/bin/env python3

# Simple script to patch SKY130 models from open_pdks with specify blocks suitable for SDF simulation

import re
import sys

SKIP_LIST = ["_tap", "flow", "probe", "conb", "decap", "diode", "fill" ]
CELL_PATH = os.environ["PDK_ROOT"] + "/skywater-pdk/libraries/sky130_fd_sc_hd/latest/cells/"

PRESPEC = r'''
    wire AWAKE          ;
    wire COND0          ;
    wire COND1          ;
    wire COND2          ;
    wire COND3          ;
    wire COND4          ;
    wire CONDB          ;
    reg notifier        ;
'''

def CheckSkip(l):
    for s in SKIP_LIST:
        if s in l:
            return False
    return True
    
def ModifySpecify(s):
    return PRESPEC + s + "\n"

in_file = open(sys.argv[1], "r")
out_file = open(sys.argv[2], "w")

pattern = re.compile("module sky130_fd_sc_hd__.*_[0-9]")

lines = in_file.readlines()
next_cell = True
for l in lines:
    if next_cell:
        if pattern.match(l):
            if CheckSkip(l):
                s = l.split('_')
                cell = s[-2]
                print("Patching model", cell)
                # prepare specify block
                with open(CELL_PATH + cell + "/" + "sky130_fd_sc_hd__" + cell + ".specify.v") as sf:
                    specify = ModifySpecify(sf.read())
                next_cell = False
    else:
        # skip to endmodule
        if "endmodule" in l:
            out_file.write(specify)
            next_cell = True
            
    out_file.write(l)
    
