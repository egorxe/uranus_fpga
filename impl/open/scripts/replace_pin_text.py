#!/usr/bin/env python3

import pya
import sys

ly = pya.Layout()
ly.read(sys.argv[2])

to_delete_power = ("VDD", "VSS")
to_replace_power = (("vdd", "VDD"), ("vss", "VSS"))
to_replace = []

with open(sys.argv[1]) as f:
    for l in f.readlines():
        if "assign" in l:
            s = l.split()
            to_replace.append((s[1], s[3][:-1]))

def replace_on_layer(layer_text, to_replace):
    rec_it = ly.top_cell().begin_shapes_rec(layer_text)
    rec_it.max_depth = 0
    for it in rec_it.each():
        s = it.shape()
        if s.is_text():
            text = s.text.string
            for t in to_replace:
                if text == t[1]:
                    new_text = s.text.dup()
                    new_text.string = t[0]
                    print("Found", t[1], "replacing with", t[0])
                    s.text = new_text

def delete_on_layer(layer_text, to_delete):
    rec_it = ly.top_cell().begin_shapes_rec(layer_text)
    rec_it.max_depth = 0
    for it in rec_it.each():
        s = it.shape()
        if s.is_text():
            text = s.text.string
            if text in to_delete:
                print("Deleting", text)
                it.shape().delete()

layer_m2 = ly.find_layer(36, 10)
layer_m3 = ly.find_layer(42, 10)
layer_m4 = ly.find_layer(46, 10)
layer_m5 = ly.find_layer(81, 10)

# regular pins
replace_on_layer(layer_m2, to_replace)
replace_on_layer(layer_m3, to_replace)

# power/ground
delete_on_layer(layer_m4, to_delete_power)
replace_on_layer(layer_m5, to_replace_power)

print("Writing result to", sys.argv[3])
ly.write(sys.argv[3])

