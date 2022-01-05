#!/usr/bin/env python3

import argparse

from params import Params

IO_IN               = 0
IO_OUT              = 1
IO_CLK              = 2

def IoCoord(i):
    s = i % p.PINS_PER_PAD
    # i //= p.PINS_PER_PAD
    # s = 1
    if i < p.LEFT_IO_END:
        return (0, (i//p.PINS_PER_PAD)+1, s)
    elif i < p.UP_IO_END:
        return ((i-p.LEFT_IO_END)//p.PINS_PER_PAD + 1, p.FPGA_FABRIC_SIZE_Y-1, s)
    elif i < p.RIGHT_IO_END:
        return (p.FPGA_FABRIC_SIZE_X-1, (i-p.UP_IO_END)//p.PINS_PER_PAD+1, s)
    elif i < p.DOWN_IO_END:
        return ((i-p.RIGHT_IO_END)//p.PINS_PER_PAD+1, 0, s)
    else:
        raise ValueError("IO number", i, "out of bounds")

def PrintPadLine(fd, port, c):
    print(port.ljust(50), str(c[0]).rjust(4,'0'), str(c[1]).rjust(4,'0'), c[2], file=fd)


# Generate .pad file
def GeneratePadFile(p, fd, ports):
    # check if enough IO is avaliable
    io_cnt = 0
    for port in ports:
        if port[1] != 0:
            io_cnt += port[1]
        else:
            io_cnt += 1
    if io_cnt > p.MAX_IO_PINS:
        print("Couldn't fit", io_cnt, "IOs into device. Maximum allowed IO number is ", p.MAX_IO_PINS)
        exit(-1)

    # generate pads
    i = 0
    for port in ports:
        if port[2] == IO_OUT:
            name = "out:" + port[0]
        else:
            name = port[0]
        if port[1] != 0:
            for n in range(port[1]):
                coord = IoCoord(p, i)
                PrintPadLine(fd, (name + '[' + str(n) + ']'), coord)
                i += 1
        else:
            coord = IoCoord(p, i)
            PrintPadLine(fd, name, coord)
            i += 1

def PutPin(of, name, pin, pins):
    pins[pin] = True
    coord = IoCoord(pin)
    PrintPadLine(of, name, coord)

parser = argparse.ArgumentParser(description="Convert FPGA pinout to VtR format")
parser.add_argument("pinout_file", type=str, help='Pinout in format "Direction Signal_name Pin_number"') 
parser.add_argument("vtr_pad_file", type=str, help='Pinout in VtR format') 
parser.add_argument("--params", type=str, help='Path to fpga params file') 
args = parser.parse_args()

if args.params:
    pfile = args.params
else:
    pfile = "../arch/params.cfg"

# Read input file
p = Params(pfile)
inf = open(args.pinout_file, "r")
of = open(args.vtr_pad_file, "w")
lines = inf.readlines()
clocks = []
pins = [False] * p.FABRIC_IO

for l in lines:
    if l.strip()[0] == "#":
        # skip comments
        continue
    s = l.split()
    pt = s[0].lower()
    if pt == "in":
        pt = IO_IN
    elif pt == "out":    
        pt = IO_OUT
    elif pt == "clk":    
        pt = IO_CLK
        clocks.append(s[1])
        continue
    else:
        print("Incorrect pin direction", pt)
        exit(-1)
    
    name = s[1]
    if pt == IO_OUT:
        name = "out:" + name    
    pin = int(s[2])
    PutPin(of, name, pin, pins)
    
# Put clocks to random empty pins
for c in clocks:
    for i in range(p.FABRIC_IO):
        if not pins[i]:
            PutPin(of, c, i, pins)
            break
