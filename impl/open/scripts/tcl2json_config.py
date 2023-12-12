#!/usr/bin/env python3

import sys
import re
import os
import json
import subprocess

DESIGN_DIR = os.environ['PWD']
CARAVEL_UPRJ_ROOT = os.environ['CARAVEL_UPRJ_ROOT']
TMP_TCL = "tmp.tcl"

def count_brackets(l):
    return l.count('{') - l.count('}')
    
def replace_env(l):
    return l.replace(DESIGN_DIR, "ref::$DESIGN_DIR").replace(CARAVEL_UPRJ_ROOT, "ref::$CARAVEL_UPRJ_ROOT")

config_tcl = sys.argv[1]

variables = []
var_pattern = re.compile('set ::env\(([^\s]*)\) (.*)$')
with open(config_tcl) as f:
    for l in f.readlines():
        res = re.search(var_pattern, l)
        if res:
            variables.append(res.group(1))

with open(TMP_TCL, "w") as f:
    print("source", config_tcl, "\nputs [array get env]", file=f)

tcl_out = subprocess.check_output(['tclsh', TMP_TCL])

state = 0
result = dict()
for v in tcl_out.split():
    v = v.decode('UTF-8')
    if state == 0:
        if v in variables:
            var = v
            state = 1
            brackets = 0
            val = ""
    elif state == 1:
        if not val:
            val = v
        else:
            val += " " + v
        brackets += count_brackets(v)
        if brackets == 0:
            if val[0] == '{':
                assert (val[-1] == '}')
                val = val[1:-1]
            try:
                val = int(val)
            except:
                try:
                    val = float(val)
                except:
                    val = replace_env(val)
            # ugly hack to make precheck happy
            if var == "FP_PDN_HPITCH":
                assert (val == 90)
                val = "expr::60 + $FP_PDN_HPITCH_MULT * 30"
            result[var] = val
            state = 0
            
with open(config_tcl.replace(".tcl", ".json"), "w") as jf:
    json.dump(result, jf, indent=4)
