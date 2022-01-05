#!/usr/bin/env python3
#
# Parse output of VPR & generate FPGA config file
#
#
###################### TODO ######################
# 1. Implement logic equvalence for logic block inputs?
# 2. Implement global constant nets
# 3. Change route parsing to load list first
# 4. Allow cell input to itself?
##################################################

import xml.etree.ElementTree
import sys
import array
import types
from copy import deepcopy
from params import Params

###################### Global constants & functions ####################


# Enum-like defines
DIR_NONE    = -1
DIR_UP      = 0
DIR_DOWN    = 1
DIR_LEFT    = 2
DIR_RIGHT   = 3

OBJTYPE_NONE    = -1
OBJTYPE_BLOCK   = 0
OBJTYPE_CHANX   = 1
OBJTYPE_CHANY   = 2
OBJTYPE_PAD     = 3

# String defines
LC_STR = "fpga_logic_cell"
LB_STR = "fpga_logic_block"
MB_STR = "fpga_memory_blck"
LB_O_STR = LB_STR + ".logic_o["
LB_I_STR = LB_STR + ".logic_i["


##################### Small helper classes & funcs #####################

class Coord(object):
    # Attributes:
    # x
    # y
    # s (subblock/track & etc)

    def __init__(self, x = -1, y = -1, s = -1):
        self.x = x
        self.y = y
        self.s = s

    def __repr__(self):
        return ('['+str(self.x)+','+str(self.y)+']') #+str(self.s)+']')

    def Direction(self, c):
        if (c.x == self.x) and (c.y < self.y):
            return DIR_DOWN
        elif (c.x == self.x) and (c.y > self.y):
            return DIR_UP
        elif (c.y == self.y) and (c.x < self.x):
            return DIR_LEFT
        elif (c.y == self.y) and (c.x > self.x):
            return DIR_RIGHT
        else:
            raise ValueError('Direction undefined: ', self, '->', c)


def InstNum(inst_str):
    return int(inst_str[inst_str.find("[")+1:inst_str.find("]")])

def CoordFromBraces(s):
    t = s[1:len(s)-1].split(',')
    return Coord(int(t[0]), int(t[1]))

# Convert direction to text
def DirToText(direction):
    if (direction == DIR_UP):
        return "UP"
    elif (direction == DIR_DOWN):
        return "DOWN"
    elif (direction == DIR_LEFT):
        return "LEFT"
    elif (direction == DIR_RIGHT):
        return "RIGHT"
    else:
        return "UNKNOWN"

########################## Config file parsers #########################

class Place_parser(object):
    # Attributes:
    # f

    def __init__(self, fname):
        self.f = open(fname, "r")

    # Returns Coord
    def CoordByName(self, name):
        self.f.seek(0, 0) # rewind file to the beginning
        for l in self.f:
            s = l.split()
            if (len(s) > 1) and (name == s[0]):
                return Coord(int(s[1]), int(s[2]), int(s[3]))
        return Coord()


class Route_parser(object):
    # VtR .route file parser - VERY ugly & slow
    # Attributes:
    # f
    # fp
    # prev_s
    # prev_coord
    # prev_chandir

    # Constructor
    def __init__(self, fname):
        self.f = open(fname, "r")
        self.fp = 0
        self.prev_s = ''
        self.prev_coord = Coord()
        self.prev_chandir = DIR_NONE

    # Parse splited route file string to know if the net terminates at output pad
    # returns [coord, mux_val] or [] if not io input
    def ParseIoIn(self, s, chandir, track):
        if (len(s) < 5) or not ('Pad' in s[4]):
            return []

        # return io coord & track number to set mux
        coord = CoordFromBraces(s[3])
        coord.s = int(s[5]) // 3    # 3 is input/output/clock
        mux_val = ({DIR_UP : p.BLK_MUX_UP_START, DIR_DOWN : p.BLK_MUX_DOWN_START, DIR_LEFT : p.BLK_MUX_LEFT_START, DIR_RIGHT : p.BLK_MUX_RIGHT_START}).get(chandir) + track
        return [coord, mux_val]


    # Parse splited route file string to get if the net terminates at block input
    # returns [coord, input_num, mux_val] or [] if not block input
    def ParseBlockIn(self, s, chandir, track):
        if (not self.StrIsBlock(s)):
            return []

        # get coords & input num from string
        coord = CoordFromBraces(s[3])
        input_num = int(s[6][len(LB_I_STR):len(s[6])-1])

        # we name directions here from source wire perspective, for logic block they'll be inversed ??? correct ???
        mux_val = ({DIR_UP : p.BLK_MUX_UP_START, DIR_DOWN : p.BLK_MUX_DOWN_START, DIR_LEFT : p.BLK_MUX_LEFT_START, DIR_RIGHT : p.BLK_MUX_RIGHT_START}).get(chandir) + track

        return [coord, input_num, mux_val]


    # Small helpers to determine object type by route string
    def StrIsChanX(self, s):
        return ('CHANX' in s[2])

    def StrIsChanY(self, s):
        return ('CHANY' in s[2])

    def StrIsChan(self, s):
        return ('CHAN' in s[2])

    def StrIsPad(self, s):
        return ('Pad' in s[4])

    def StrIsBlock(self, s):
        return (LB_STR in s[6]) or (MB_STR in s[6])

    def GetObjectType(self, s):
        if self.StrIsBlock(s):
            return OBJTYPE_BLOCK
        elif self.StrIsPad(s):
            return OBJTYPE_PAD
        elif self.StrIsChanX(s):
            return OBJTYPE_CHANX
        elif self.StrIsChanY(s):
            return OBJTYPE_CHANY
        else:
            raise ValueError("Failed to determine object from routing string: ", s)

    def ChanDirToType(self, chandir):
        if (chandir == DIR_UP) or (chandir == DIR_DOWN):
            return OBJTYPE_CHANY
        elif (chandir == DIR_LEFT) or (chandir == DIR_RIGHT):
            return OBJTYPE_CHANX

    def GetTrack(self, s):
        track = int(s[5])
        # VTR counts tracks in both directions, we in each direction separately
        track = int(track / 2)# + (track % 1)
        if (track < 0) or (track >= p.TRACKS_PER_RNODE):
            raise ValueError("Wrong track number ", track, " out of ", p.TRACKS_PER_RNODE)
        return track

    # Determine channel direction from splitted string (! use the fact that right and up have even node numbers !)
    def GetChandir(self, s):
        objtype = self.GetObjectType(s)
        nodenum = int(s[1])
        if (objtype == OBJTYPE_CHANX):
            if (nodenum % 2) == 0:
                return DIR_RIGHT
            else:
                return DIR_LEFT
        elif (objtype == OBJTYPE_CHANY):
            if (nodenum % 2) == 0:
                return DIR_UP
            else:
                return DIR_DOWN
        else:
            raise ValueError("Incorrect objtype!")

    # Direction helper
    def GetDirection(self, stype, _scoord, dtype, _dcoord):
        # ! ugly to get rid of mutability
        scoord = deepcopy(_scoord)
        dcoord = deepcopy(_dcoord)

        # offset channel coords by 0.5
        if (stype == OBJTYPE_CHANX):
            scoord.y += 0.5
        if (dtype == OBJTYPE_CHANX):
            dcoord.y += 0.5
        if (stype == OBJTYPE_CHANY):
            scoord.x += 0.5
        if (dtype == OBJTYPE_CHANY):
            dcoord.x += 0.5

        # use simple direction for everything but the case of two different channels
        if (stype == OBJTYPE_CHANX) and (dtype == OBJTYPE_CHANY):
            if (dcoord.y > scoord.y) and (abs(dcoord.x - scoord.x) <= 1):
                return DIR_UP
            elif (dcoord.y <= scoord.y) and (abs(dcoord.x - scoord.x) <= 1):
                return DIR_DOWN
            else:
                raise ValueError("Error in determining channel direction: ", scoord, "->", dcoord)

        if (stype == OBJTYPE_CHANY) and (dtype == OBJTYPE_CHANX):
            if (dcoord.x > scoord.x) and (abs(dcoord.y - scoord.y) <= 1):
                return DIR_RIGHT
            elif (dcoord.x <= scoord.x) and (abs(dcoord.y - scoord.y) <= 1):
                return DIR_LEFT
            else:
                raise ValueError("Error in determining channel direction: ", scoord, "->", dcoord)

        return scoord.Direction(dcoord)

    # Check that mux is Wilton-type (seems to be correct for any p.TRACKS_PER_RNODE value)
    def CheckSwitch(self, chandir, mux_state, strack, dtrack, coord, s):
        expected = -1
        if (mux_state == p.FORWARD_MUX_START):
            expected = strack
        elif (chandir == DIR_UP):
            if (mux_state == p.LEFT_MUX_START):
                expected = strack + 1
            elif (mux_state == p.RIGHT_MUX_START):
                expected = (p.TRACKS_PER_RNODE-2) - strack
            else:
                raise ValueError("Incorrect mux state", mux_state)
        elif (chandir == DIR_DOWN):
            if (mux_state == p.LEFT_MUX_START):
                expected = strack + 1
            elif (mux_state == p.RIGHT_MUX_START):
                expected = 0 - strack
            else:
                raise ValueError("Incorrect mux state", mux_state)
        elif (chandir == DIR_RIGHT):
            if (mux_state == p.LEFT_MUX_START):
                expected = 0 - strack
            elif (mux_state == p.RIGHT_MUX_START):
                expected = strack - 1
            else:
                raise ValueError("Incorrect mux state", mux_state)
        elif (chandir == DIR_LEFT):
            if (mux_state == p.LEFT_MUX_START):
                expected = (p.TRACKS_PER_RNODE-2) - strack
            elif (mux_state == p.RIGHT_MUX_START):
                expected = strack - 1
            else:
                raise ValueError("Incorrect mux state", mux_state)
        else:
            raise ValueError("Incorrect direction", chandir)

        # patch overflow
        if (expected >= p.TRACKS_PER_RNODE):
            expected -= p.TRACKS_PER_RNODE
        elif (expected < 0):
            expected += p.TRACKS_PER_RNODE

        # sanity check
        if (expected < 0) or (expected >= p.TRACKS_PER_RNODE):
            raise ValueError("Wrong expected track ", expected)

        if (dtrack != expected):
            raise ValueError("Unsupported switch configuration: ", mux_state, strack, DirToText(chandir), "->", dtrack, coord, s, " expected ", expected)


    # Get mux state for block->chan based on relative position
    def ChanFromBlockMux(self, objtype, bcoord, ccoord, chandir, pin):
        loc = self.GetDirection(objtype, bcoord, self.ChanDirToType(chandir), ccoord)
        if (objtype == OBJTYPE_PAD) and ((pin < 0) or (pin >= p.PINS_PER_PAD)):
            raise ValueError("Wrong IO pin number", pin)
            
        if (objtype == OBJTYPE_BLOCK):
            off = (pin // p.BLOCK_SIDES)
        else:
            off = 0

        if (loc == DIR_UP):
            if (objtype == OBJTYPE_BLOCK) and ((pin < 0) or (pin >= p.BLOCK_OUTPUTS) or (pin % p.BLOCK_SIDES != 0)):
                raise ValueError("Wrong block pin number: ", bcoord, DirToText(loc), pin)
            return p.BLOCK_R_MUX_START + off
        elif (loc == DIR_RIGHT):
            if (objtype == OBJTYPE_BLOCK) and ((pin < 0) or (pin >= p.BLOCK_OUTPUTS) or (pin % p.BLOCK_SIDES != 1)):
                raise ValueError("Wrong block pin number: ", bcoord, DirToText(loc), pin)
            return p.BLOCK_L_MUX_START + off
        elif (loc == DIR_DOWN):
            if (objtype == OBJTYPE_BLOCK) and ((pin < 0) or (pin >= p.BLOCK_OUTPUTS) or (pin % p.BLOCK_SIDES != 2)):
                raise ValueError("Wrong block pin number: ", bcoord, DirToText(loc), pin)
            return p.BLOCK_L_MUX_START + off
        elif (loc == DIR_LEFT):
            if (objtype == OBJTYPE_BLOCK) and ((pin < 0) or (pin >= p.BLOCK_OUTPUTS) or (pin % p.BLOCK_SIDES != 3)):
                raise ValueError("Wrong block pin number: ", bcoord, DirToText(loc), pin)
            return p.BLOCK_R_MUX_START + off
        else:
            raise ValueError("WTF?")



    # Parse splited route file string to get source mux value for CHAN
    # Mux mapping:
    # MUX_PER_CLASS     : lefter or upper fpga_block outputs
    # MUX_PER_CLASS     : righter or lower fpga_block outputs
    # MUX_PER_CLASS     : forward
    # MUX_PER_CLASS     : left
    # MUX_PER_CLASS     : right
    def ParseSrcMux(self, s, c, prev_c, chandir, prev_chandir):
        if self.StrIsPad(s):
            # parse IO block - just return the pin number
            io_pin = (int(s[5]) - 1) // 3    # cause there are in/out/clock pins in VtR
            #io_pin = int(s[5] - p.IN_PINS_PER_PAD
            return self.ChanFromBlockMux(OBJTYPE_PAD, prev_c, c, chandir, io_pin)
        elif self.StrIsBlock(s):
            # parse logic block - set to output number
            block_pin = int(s[6][len(LB_O_STR):len(s[6])-1])
            return self.ChanFromBlockMux(OBJTYPE_BLOCK, prev_c, c, chandir, block_pin)
        elif self.StrIsChan(s):
            # parse channels
            track = self.GetTrack(s)

            if (prev_chandir == chandir):
                mux_state = p.FORWARD_MUX_START
            elif (prev_chandir == DIR_UP):
                if (chandir == DIR_RIGHT):
                    mux_state = p.RIGHT_MUX_START
                elif (chandir == DIR_LEFT):
                    mux_state = p.LEFT_MUX_START
                else:
                    raise ValueError("Direction error!")
            elif (prev_chandir == DIR_DOWN):
                if (chandir == DIR_LEFT):
                    mux_state = p.RIGHT_MUX_START
                elif (chandir == DIR_RIGHT):
                    mux_state = p.LEFT_MUX_START
                else:
                    raise ValueError("Direction error!")
            elif (prev_chandir == DIR_LEFT):
                if (chandir == DIR_UP):
                    mux_state = p.RIGHT_MUX_START
                elif (chandir == DIR_DOWN):
                    mux_state = p.LEFT_MUX_START
                else:
                    raise ValueError("Direction error!")
            elif (prev_chandir == DIR_RIGHT):
                if (chandir == DIR_DOWN):
                    mux_state = p.RIGHT_MUX_START
                elif (chandir == DIR_UP):
                    mux_state = p.LEFT_MUX_START
                else:
                    raise ValueError("Direction error!")
            else:
                raise ValueError("Direction error!")

            # mux sanity check
            self.CheckSwitch(prev_chandir, mux_state, track, c.t, c, s)
            return mux_state
        else:
            raise ValueError('Error in route file, unexpected net source: ', s)


    # Returns (x, y, chandir, track, smux, [block_in], [io_in])
    def GetNextChan(self):
        res = types.SimpleNamespace(x=-1, y=-1, chandir=-1, smux=-1, track = -1, block_in = [], io_in = [])
        coord = Coord()
        for l in self.f:
            s = l.split()
            # track the file pointer
            self.fp += len(l)

            # every node has coords (needed for next)
            if (len(s) > 0) and ('Node' in s[0]):
                # get coords
                coord = CoordFromBraces(s[3])

            # search for CHAN directives
            if (len(s) > 2) and ('CHAN' in s[2]):
                res.x = coord.x
                res.y = coord.y

                res.chandir = self.GetChandir(s)

                # sanity check
                if (((res.chandir == DIR_UP) or (res.chandir == DIR_DOWN)) and self.StrIsChanY(s)):
                    pass
                elif (((res.chandir == DIR_LEFT) or (res.chandir == DIR_RIGHT)) and self.StrIsChanX(s)):
                    pass
                else:
                    raise ValueError('Unsupported CHAN or wrong direction in route file: ', s[2], res.chandir)

                coord.t = self.GetTrack(s)
                res.track = coord.t

                # look in previous string to get source mux state
                res.smux = self.ParseSrcMux(self.prev_s, coord, self.prev_coord, res.chandir, self.prev_chandir)

                # look in next string and rewind
                next_s = self.f.readline().split()
                self.f.seek(self.fp)
                if not res.block_in:
                    res.block_in = self.ParseBlockIn(next_s, res.chandir, res.track)
                if (not res.block_in) and (not res.io_in):
                    res.io_in = self.ParseIoIn(next_s, res.chandir, res.track)

                # remember previous string
                self.prev_s = s
                self.prev_coord = coord
                self.prev_chandir = res.chandir

                # return result
                return res #[coord, chandir, track, smux, block_in, io]

            # remember previous string if it is not a SINK
            if (len(s) > 4) and (s[2] != "SINK") and (s[2] != "IPIN"):
                self.prev_s = s
                self.prev_coord = coord
            elif (len(s) > 2) and (s[2] == "SINK"):
                # on SINK skip next line
                l = self.f.readline()
                self.prev_s = l.split()
                self.fp += len(l)
                if len(self.prev_s) > 4 and self.StrIsChan(self.prev_s):
                    self.prev_coord = CoordFromBraces(self.prev_s[3])
                    self.prev_chandir = self.GetChandir(self.prev_s)
                    # ! very ugly hack to support IPIN immediately after SINK - read one more line !
                    # look in next string and rewind
                    next_s = self.f.readline().split()
                    self.f.seek(self.fp)
                    res.block_in = self.ParseBlockIn(next_s, self.prev_chandir, self.GetTrack(self.prev_s))
                    if not res.block_in:
                        res.io_in = self.ParseIoIn(next_s, self.prev_chandir, self.GetTrack(self.prev_s))
                    if res.block_in or res.io_in:
                        return res
                    # ! ugly hack !
                elif len(self.prev_s) > 4 and (self.StrIsPad(self.prev_s) or self.StrIsBlock(self.prev_s)):
                    self.prev_coord = CoordFromBraces(self.prev_s[3])


        return res


# Very simple, ugly & incomplete blif parser to load LUT contents
class Blif_parser(object):
    # Attributes:
    # f

    def __init__(self, fname):
        self.f = open(fname, "r")


    def PopulateLutLists(self, l):
        for j in range(len(l)):
            for k in range(len(l[j])):
                if l[j][k] == '-':
                    tmp = list(l[j])
                    tmp[k] = '1'
                    l[j][k] = '0'
                    l.append(tmp)
                    return False
        return True


    def LoadLut(self, name, rotation_map):
        # parse rotation map
        s = rotation_map.split()
        used_list = []
        open_list = []
        rotation_swap = list(range(p.FPGA_LUT_WIDTH))
        for i in range(len(s)):
            if (s[i] != "open"):
                used_list.append(int(s[i]))
            else:
                open_list.append(i)
        open_set = set(rotation_swap) - set(used_list)
        for i in range(len(s)):
            if (s[i] != "open"):
                j = int(s[i])
                rotation_swap[j] = i

        # fix open positions (ugly)
        cnt = 0
        for i in open_set:
            rotation_swap[i] = open_list[cnt]
            cnt+=1

        # sanity check rotation map
        for i in range(len(rotation_swap)):
            for j in range(len(rotation_swap)):
                if (i != j) and (rotation_swap[i] == rotation_swap[j]):
                    raise ValueError("Incorrect rotation map: ", rotation_swap, rotation_map)

        lut = 0
        self.f.seek(0, 0) # rewind blif file to the beginning
        line = self.f.readline()
        lut_bits_list = []
        found = False
        while not ('.end' in line):
            sline = line.split()
            if (len(sline) >= 2) and ('.names' == sline[0]) and (name == sline[len(sline)-1]):
                logic_line = self.f.readline()
                logic_line_part = logic_line.split()
                i = 0
                found = True

                # $true & $false are special cases :(
                if (len(logic_line_part) == 1) and (logic_line_part[0] == "1"):
                    names_type = 1
                    lut_bits_list.append((1 << p.FPGA_LUT_SIZE)-1)
                    break   # $true
                elif (logic_line_part[0] == ".names"):
                    names_type = 1
                    break   # $false

                if (len(logic_line_part) != 2):
                    raise ValueError(".names format error in blif!")

                names_type = int(logic_line_part[1])   # all 0s or all 1s LUT
                if names_type == 0:
                    # inverse names LUT
                    lut = (1 << p.FPGA_LUT_WIDTH)-1
                elif names_type == 1:
                    pass
                else:
                    raise ValueError(".names format error in blif!")

                while not ('.' == logic_line[0]):
                    if i >= p.FPGA_LUT_SIZE:
                        raise ValueError(".names larger than LUT!")
                    i = i + 1

                    # apply rotation map by swapping characters (ugly)
                    lut_list = list((logic_line_part[0].ljust(p.FPGA_LUT_WIDTH, '-'))) # fill_char
                    lut_list_rot = [0] * p.FPGA_LUT_WIDTH
                    for j in range(len(rotation_swap)):
                        lut_list_rot[rotation_swap[j]] = lut_list[j]

                    # replicate strings with '-' character replacing them with 0 & 1
                    lut_lists = [lut_list_rot]
                    while (not self.PopulateLutLists(lut_lists)):
                        pass

                    # calculate lut bits
                    for lut_list_str in lut_lists:
                        lut_sel = 1 << int("".join(reversed(lut_list_str)), 2)
                        lut_bits_list.append(lut_sel)
                    logic_line = self.f.readline()
                    logic_line_part = logic_line.split()
                # line = logic_line
                break
            else:
                line = self.f.readline()

        if not found:
            raise ValueError("LUT with name ", name, " not found")
        # remove duplicate bits & sum final lut content
        lut_bit_set = set(lut_bits_list)
        for lut_sel in lut_bit_set:
            if names_type == 0:
                lut -= lut_sel
            else:
                lut += lut_sel

        # sanity check & return
        if (lut < 0) or (lut >= (1 << p.FPGA_LUT_SIZE)):
            raise ValueError("Incorrect LUT ", name, " val: ", lut)
        return lut


############################## Logic cell ##############################

class Logic_cell(object):
    # Attributes:
    #
    # name
    # instance
    # lut
    # inputs
    # mux

    def __init__(self, cell_num, name = 'open', instance = '-', inputs_str = '', mux = 0):
        self.cell_num = cell_num
        self.name = name
        self.instance = instance
        self.lut = 0
        self.inputs = array.array('b', [-1] * p.CELL_INPUTS)    # crossbar
        self.mux = mux
        inputs_list = inputs_str.split()
        for i in range(len(inputs_list)):
            if (LB_I_STR in inputs_list[i]):
                # block input
                num = InstNum(inputs_list[i])
                if (num < i*p.LBCROSS_INPUTS) or (num >= ((i+1)*p.LBCROSS_INPUTS)):
                    raise ValueError("Wrong block input number for cell input", i, "mux connection: ", inputs_list[i])
                num -= i*p.LBCROSS_INPUTS
                self.inputs[i] = p.CELL_IN_MUX_START + num
            elif (LC_STR in inputs_list[i]):
                # cell N output
                num = InstNum(inputs_list[i])
                if (num == InstNum(instance)):
                    raise ValueError("Cell input taken from same cell output is not allowed")
                self.inputs[i] = p.CELL_LUT_MUX_START + num
            elif (inputs_list[i] != 'open'):
                raise ValueError("Unexpected cell input in net-file: ", inputs_list[i])

    def SetName(self, name):
        self.name = name

    def SetInstance(self, instance):
        self.instance = instance

    def SetInput(self, i, v):
        self.inputs[i] = v

    def GetInputs(self):
        r = []
        for i in self.inputs:
            if (i >= 0):
                r.append(i)
            else:
                # this is not very elegant input zeroing
                #???may be it could be removed in case of more proper wire-lut or smth??
                r.append(self.cell_num)
        return r

    def SetLut(self, lut):
        # sanity check
        if (lut < 0) or (lut >= (1 << p.FPGA_LUT_SIZE)):
            raise ValueError("Incorrect LUT ", self.name, " val: ", lut)
        self.lut = lut

    def LoadFromBlif(self, blif, rotation_map):
        self.SetLut(blif.LoadLut(self.name, rotation_map))

    def PrintInputs(self, f):
        for i in self.GetInputs():
            print(i, end=' ', file=f)

    def PrintLut(self, f):
        print("0x{:04X}".format(self.lut), end=' ', file=f)

    def PrintMux(self, f):
        print(self.mux, end=' ', file=f)

    def PrintID(self, f):
        print("\n# Logic cell ", self.instance, file=f)

    def Print(self, f):
        self.PrintID(f)
        self.PrintInputs(f)
        self.PrintLut(f)
        self.PrintMux(f)



############################# Logic block ##############################

class Logic_block(object):
    # Attributes:
    #
    # name
    # instance
    # cells
    # coord
    # inputs


    def __init__(self, coord):
        self.name = ''
        self.instance = ''
        self.cells = []
        for i in range(p.CELLS_PER_BLOCK):
            self.cells.append(Logic_cell(i))
        self.coord = coord
        self.inputs = array.array('h', [-1] * p.BLOCK_INPUTS) # block input muxes


    def SetName(self, name):
        self.name = name


    def SetInstance(self, instance):
        self.instance = instance


    def SetCellFromBlif(self, i, cell, blif, rotation_map = ""):
        if (i != cell.cell_num):
            raise ValueError("Cell number mismatch!")
        self.cells[i] = cell
        self.cells[i].LoadFromBlif(blif, rotation_map)


    def SetCellFromVal(self, i, cell, lut_val):
        if (i != cell.cell_num):
            raise ValueError("Cell number mismatch!")
        self.cells[i] = cell
        self.cells[i].SetLut(lut_val)


    def SetInput(self, i, val):
        self.inputs[i] = val


    def LoadFromXml(self, block, blif):
        for cell_block in block.findall("block"):
            if cell_block.get("mode") == "n1_lut4":
                inst = cell_block.get("instance")
                cell_num = InstNum(inst)
                inputs_str = cell_block.find("inputs").find("port").text
                # ? we assume here that LUT block will always be first ?
                lut_block = cell_block.find("block")
                lut_mode = lut_block.get("mode")

                # check if register is used
                if ("fpga_register" in cell_block.find("outputs").find("port").text):
                    mux = 1
                else:
                    mux = 0

                cell = Logic_cell(cell_num, lut_block.get("name"), inst, inputs_str, mux)

                # check LUT mode
                if (lut_mode == "fpga_lut"):
                    rotation_map = lut_block.find("block").find("inputs").find("port_rotation_map")
                    if rotation_map == None:
                        # gen 0 1 2 3 rotation map
                        rotation_map_text = ""
                        for i in range(p.FPGA_LUT_WIDTH):
                            if i != 0:
                                rotation_map_text += " "
                            rotation_map_text += str(i)
                    else:
                        rotation_map_text = rotation_map.text
                    self.SetCellFromBlif(cell_num, cell, blif, rotation_map_text)
                elif (lut_mode == "wire"):
                    # print("Wire mode lut ", block.get("instance"), ":", inst)
                    # find which input should be connected in LUT
                    lut_input_str = lut_block.find("inputs").find("port").text.split()
                    lut_val = -1
                    for i in range(len(lut_input_str)):
                        if (lut_input_str[i] != "open"):
                            if (lut_val >= 0):
                                raise ValueError("Several input ports \"" + lut_input_str + "\" in wire LUT for", block.get("instance"), ":", inst)
                            lut_val = 1 << (1 <<  i)
                    self.SetCellFromVal(cell_num, cell, lut_val)
                else:
                    raise ValueError("Unsupported LUT mode", lut_mode, "in", block.get("instance"), ":", inst)


    def GetBInputs(self):
        r = []
        for l in self.inputs:
            r.append(l//p.BLOCK_IN_MUXES_COEF)
        return r

    def PrintBInputs(self, f):
        print("\n# Block input muxes:", file=f)
        bi = self.GetBInputs()
        for i in bi:
            print(i, end=' ', file=f)


    def PrintCells(self, f):
        for l in self.cells:
            l.PrintInputs(f)
        for l in self.cells:
            l.PrintLut(f)
        for l in self.cells:
            l.PrintMux(f)

    def PrintID(self, f):
        print("\n# Logic block ", self.coord, ":", file=f)


    def Print(self, f):
        self.PrintID(f)

        for l in self.cells:
             l.Print(f)
        self.PrintBInputs(f)

        print(file=f)


########################### Routing_node ###############################

class Routing_node(object):
    # Attributes:
    #
    # tracks
    # x
    # y
    # direction

    def __init__(self, x = -1, y = -1, direction = DIR_NONE):
        self.tracks = [-1] * p.TRACKS_PER_RNODE
        self.coord = Coord(x, y)
        self.direction = direction

    def SetTrack(self, t, smux):
        self.tracks[t] = smux

    def GetTracks(self):
        return self.tracks

    def PrintID(self, f):
        print("\n# " + DirToText(self.direction) + " routing node at ", self.coord, file=f)

    def Print(self, f):
        self.PrintID(f)
        for t in self.tracks:
            print(t, file=f, end=' ')
        print(file=f)


######################### Other FPGA blocks ############################

# IO block
class IO_block(object):
    # Attributes:
    #
    # name
    # instance
    # mode
    # tracks
    # coord

    def __init__(self, coord):
        self.mode = ['none'] * p.PINS_PER_PAD
        self.instance = [''] * p.PINS_PER_PAD
        self.name = [''] * p.PINS_PER_PAD
        self.tracks = [-2] * p.PINS_PER_PAD
        self.coord = coord

    def LoadFromXml(self, pin, block):
        self.mode[pin] = block.get('mode')
        self.name[pin] = block.get('name')
        self.instance[pin] = block.get('instance')

    def SetTrack(self, track, pin):
        self.tracks[pin] = track
        #print("IO block", self.mode, self.name, self.instance, self.track)

    def GetIOMuxes(self):
        out = []
        for i in range(p.PINS_PER_PAD):
            if self.mode[i] == 'outpad':
                out.append(self.tracks[i]//p.BLOCK_IN_MUXES_COEF)
            else:
                out.append(-1)
        return reversed(out)

    def PrintID(self, f):
        print("\n# IO at ", self.coord, file=f)

    def Print(self, f):
        self.PrintID(f)
        print(self.GetIOMuxes(), file=f)


# Empty block placeholder
class Empty_block(object):

    def __init__(self, coord):
        self.coord = coord

    def PrintID(self, f):
        print("\n# Empty placeholder at ", self.coord, file=f)

    def Print(self, f):
        self.PrintID(f)
        print(-1, file=f)


############################# FPGA fabric ##############################

class Fpga_fabric:
    # Attributes:
    #
    # fabric
    # routing_v
    # routing_h
    # size_x
    # size_y

    def __init__(self, size_x, size_y):
        self.size_x = size_x
        self.size_y = size_y
        self.fabric = [[Empty_block(Coord())] * self.SizeY() for i in range(self.SizeX())]
        self.routing_u = [[Routing_node(x,y+1,DIR_UP) for y in range(self.RoutingVSizeY())] for x in range(self.RoutingVSizeX())]
        self.routing_d = [[Routing_node(x,y+1,DIR_DOWN) for y in range(self.RoutingVSizeY())] for x in range(self.RoutingVSizeX())]
        self.routing_l = [[Routing_node(x+1,y,DIR_LEFT) for y in range(self.RoutingHSizeY())] for x in range(self.RoutingHSizeX())]
        self.routing_r = [[Routing_node(x+1,y,DIR_RIGHT) for y in range(self.RoutingHSizeY())] for x in range(self.RoutingHSizeX())]

        # Construct FPGA fabric array
        for x in range(self.SizeX()):
            for y in range(self.SizeY()):
                if self.IsEmpty(x, y):
                    # corners are empty
                    self.fabric[x][y] = Empty_block(Coord(x,y))
                elif self.IsIoBlock(x, y):
                    # put io blocks on edges
                    self.fabric[x][y] = IO_block(Coord(x,y))
                else:
                    # put logic blocks everywhere else
                    self.fabric[x][y] = Logic_block(Coord(x, y))


    # Load from VTR files
    def Load(self, net_file, place_file, blif_file, route_file):
        # parse .net file
        print('Processing logic blocks...')
        for block in net_file.findall('block'):
            inst_str = block.get('instance')
            name = block.get('name')
            # num = InstNum(inst_str)
            coord = place_file.CoordByName(name)
            if 'fpga_logic_block' in inst_str:
                # logic block
                if not self.IsLogicBlock(coord.x, coord.y):
                    raise ValueError('Failed to find logic block with name', name, 'in placer file!', coord)
                self.fabric[coord.x][coord.y].LoadFromXml(block, blif_file)

            elif 'io' in inst_str:
                # IO block
                if (coord.x < 0) or (coord.y < 0):
                    raise ValueError('Failed to find IO block with name', name, 'in placer file!')
                if not self.IsIoBlock(coord.x, coord.y):
                    raise ValueError('Unexpected position for IO block', name, 'in placer file:', coord)
                self.fabric[coord.x][coord.y].LoadFromXml(coord.s, block)

        # Parse .route file
        print('Processing nets...')

        while True:
            chan = route_file.GetNextChan()
            if (chan.x < 0) and (not chan.block_in) and (not chan.io_in):
                # no more nets in route file
                break

            if chan.block_in:
                # if this net terminates to logic block - set input mux
                self.fabric[chan.block_in[0].x][chan.block_in[0].y].SetInput(chan.block_in[1], chan.block_in[2])

            if chan.io_in:
                # if this net terminates to io pad - set input mux
                self.fabric[chan.io_in[0].x][chan.io_in[0].y].SetTrack(chan.io_in[1], chan.io_in[0].s)

            # set appropriate routing muxes
            if (chan.x >= 0):
                if (chan.chandir == DIR_UP) and (chan.y >= 1):
                    self.routing_u[chan.x][chan.y-1].SetTrack(chan.track, chan.smux)
                elif (chan.chandir == DIR_DOWN) and (chan.y >= 1):
                    self.routing_d[chan.x][chan.y-1].SetTrack(chan.track, chan.smux)
                elif (chan.chandir == DIR_LEFT) and (chan.x >= 1):
                    self.routing_l[chan.x-1][chan.y].SetTrack(chan.track, chan.smux)
                elif (chan.chandir == DIR_RIGHT) and (chan.x >= 1):
                    self.routing_r[chan.x-1][chan.y].SetTrack(chan.track, chan.smux)
                else:
                    raise ValueError('Invalid chan from route parser:', chan)


    # Positional stuff
    def SizeX(self):
        return self.size_x

    def SizeY(self):
        return self.size_y

    def RoutingVSizeX(self):
        return self.size_x-1

    def RoutingVSizeY(self):
        return self.size_y-2

    def RoutingHSizeX(self):
        return self.size_x-2

    def RoutingHSizeY(self):
        return self.size_y-1

    def IsInside(self, x, y):
        if (x >= 0) and (y >= 0) and (x < self.SizeX()) and (y < self.SizeY()):
            return True
        else:
            return False

    def IsCorner(self, x, y):
        if ((x == 0) or (x == self.SizeX()-1)) and ((y == 0) or (y == self.SizeY()-1)):
            return True
        else:
            return False

    def IsEdge(self, x, y):
        if ((x == 0) or (y == 0) or (x == self.SizeX()-1) or (y == self.SizeY()-1)) and (not self.IsCorner(x, y)):
            return True
        else:
            return False

    def IsLogicBlock(self, x, y):
        if self.IsInside(x, y) and (not self.IsEdge(x, y)):
            return True
        else:
            return False

    def IsIoBlock(self, x, y):
        if self.IsEdge(x, y) and (not self.IsCorner(x, y)):
            return True
        else:
            return False

    def IsEmpty(self, x, y):
        return self.IsCorner(x, y)


    # Print resulting config
    def Print(self, f):
        print('# FPGA fabric & IO', file=f)
        for l in self.fabric:
            for b in l:
                b.Print(f)

        print('# Routing up', file=f)
        for l in self.routing_u:
            for r in l:
                r.Print(f)

        print('# Routing down', file=f)
        for l in self.routing_d:
            for r in l:
                r.Print(f)

        print('# Routing left', file=f)
        for l in self.routing_l:
            for r in l:
                r.Print(f)

        print('# Routing right', file=f)
        for l in self.routing_r:
            for r in l:
                r.Print(f)

    # Bitstream for loader
    def WriteBitstream(self, fname):
        
        out_bit_file = open(fname + ".bit", 'w')
        out_c_file_lb = open(fname + "_lb_bit.h", 'w')
        out_c_file_vn = open(fname + "_vn_bit.h", 'w')
        out_c_file_hn = open(fname + "_hn_bit.h", 'w')

        block_bitlines  = ["" for x in range(1, self.SizeX()-1)]
        vrnode_bitlines = ["" for y in range(0, self.RoutingVSizeY())]
        hrnode_bitlines = ["" for x in range(0, self.RoutingHSizeX())]

        # Construct data for config_block chain
        for y in range(1, self.SizeY()-1):
            for x in range(1, self.SizeX()-1):
                b = self.fabric[x][y]
                if type(b) == Logic_block:
                    # block input muxes
                    block_bitlines[x-1] += ListToBitline(b.GetBInputs(), p.BINPUT_MUX_STATE_WDT)
                    for c in b.cells:
                        # cell input mux (crossbar)
                        block_bitlines[x-1] += (ListToBitline(c.GetInputs(), p.LBCROSS_MUX_STATE_WDT))
                    for c in b.cells:
                        # cell LUT
                        block_bitlines[x-1] += (ListToBitline([c.lut], p.FPGA_LUT_SIZE))
                        # cell MUX
                        block_bitlines[x-1] += (ListToBitline([c.mux], 1))
                else:
                    raise ValueError("No logic block at", x, y)

        # Construct data for config_vrnode chain
        for y in range(0, self.RoutingVSizeY()):
            # IO muxes left
            vrnode_bitlines[y] += (ListToBitline(self.fabric[0][y+1].GetIOMuxes(), p.BINPUT_MUX_STATE_WDT))
            for x in range(0, self.RoutingVSizeX()):
                un = self.routing_u[x][y]
                dn = self.routing_d[x][y]
                if (type(un) == Routing_node) and (type(dn) == Routing_node):
                    # up node
                    vrnode_bitlines[y] += (ListToBitline((un.GetTracks()), p.RNODE_MUX_STATE_WDT))
                    # down node
                    vrnode_bitlines[y] += (ListToBitline((dn.GetTracks()), p.RNODE_MUX_STATE_WDT))
                else:
                    raise ValueError("No routing node at", x, y)
            # IO muxes right
            vrnode_bitlines[y] += (ListToBitline(self.fabric[self.SizeX()-1][y+1].GetIOMuxes(), p.BINPUT_MUX_STATE_WDT))

        # Construct data for config_hrnode chain
        for x in range(0, self.RoutingHSizeX()):
            # IO muxes down
            hrnode_bitlines[x] += (ListToBitline(self.fabric[x+1][0].GetIOMuxes(), p.BINPUT_MUX_STATE_WDT))
            for y in range(0, self.RoutingHSizeY()):
                ln = self.routing_l[x][y]
                rn = self.routing_r[x][y]
                if (type(ln) == Routing_node) and (type(rn) == Routing_node):
                    # left node
                    hrnode_bitlines[x] += (ListToBitline((ln.GetTracks()), p.RNODE_MUX_STATE_WDT))
                    # right node
                    hrnode_bitlines[x] += (ListToBitline((rn.GetTracks()), p.RNODE_MUX_STATE_WDT))
                else:
                    raise ValueError("No routing node at", x, y)
            # IO muxes up
            hrnode_bitlines[x] += (ListToBitline(self.fabric[x+1][self.SizeY()-1].GetIOMuxes(), p.BINPUT_MUX_STATE_WDT))

        # Write result
        i = 0
        comment = "// Bitstream generated from " + fname
        print(comment + "\nconst uint16_t lblock_config_data[] = {", file = out_c_file_lb)
        print(comment + "\nconst uint16_t vnode_config_data[] = {", file = out_c_file_vn)
        print(comment + "\nconst uint16_t hnode_config_data[] = {", file = out_c_file_hn)
        while (i < p.BLOCK_CFGCHAIN_LEN) or (i < p.VRNODE_CFGCHAIN_LEN) or (i < p.HRNODE_CFGCHAIN_LEN):
            lb = ""
            if (i < p.BLOCK_CFGCHAIN_LEN):
                # write one bit for each config line for logic blocks
                for l in block_bitlines:
                    lb += l[i]
            vn = ""
            if (i < p.VRNODE_CFGCHAIN_LEN):
                # write one bit for each config line for vertical routing nodes blocks
                for l in vrnode_bitlines:
                    vn += l[i]
            hn = ""
            if (i < p.HRNODE_CFGCHAIN_LEN):
                # write one bit for each config line for horizontal routing nodes blocks
                for l in hrnode_bitlines:
                    hn += l[i]

            print(lb + " " + vn + " " + hn, file=out_bit_file)
            if lb:
                if i:
                    print(",", file=out_c_file_lb)
                print(hex(int(lb[::-1], 2)), file=out_c_file_lb, end="")
            if vn:
                if i:
                    print(",", file=out_c_file_vn)
                print(hex(int(vn[::-1], 2)), file=out_c_file_vn, end="")
            if hn:
                if i:
                    print(",", file=out_c_file_hn)
                print(hex(int(hn[::-1], 2)), file=out_c_file_hn, end="")
            i += 1
        print("};\nconst int lblock_config_words = sizeof(lblock_config_data)/sizeof(lblock_config_data[0]);\n", file = out_c_file_lb)
        print("};\nconst int vnode_config_words = sizeof(vnode_config_data)/sizeof(vnode_config_data[0]);\n", file = out_c_file_vn)
        print("};\nconst int hnode_config_words = sizeof(hnode_config_data)/sizeof(hnode_config_data[0]);\n", file = out_c_file_hn)

def ListToBitline(lst, length):
    s = ""
    for e in lst:
        if e < 0:
            s += "1" * length
        else:
            s += (("{0:0"+str(length)+"b}").format(e))[::-1]    # reversed!
    return s


################################# MAIN #################################

# Parse parameters
if len(sys.argv) < 4:
    print('Usage: bitgen.py arch_params_file vtr_files_basename output_file')
    exit(1)

p = Params(sys.argv[1])

base_name = sys.argv[2]
out_name = sys.argv[3]

# Open files
blif_file = Blif_parser(base_name + '.eblif')
net_file = xml.etree.ElementTree.parse(base_name + '.net').getroot()
place_file = Place_parser(base_name + '.place')
route_file = Route_parser(base_name + '.route')
out_file = open(out_name, 'w')

# Create fabric
fpga_fabric = Fpga_fabric(p.FPGA_FABRIC_SIZE_X, p.FPGA_FABRIC_SIZE_Y)
fpga_fabric.Load(net_file, place_file, blif_file, route_file)

# Write fabric bitstream
print('Writing config to output files...')
fpga_fabric.Print(out_file)
fpga_fabric.WriteBitstream(out_name)

print('Bitgen completed!')
