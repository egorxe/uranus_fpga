#!/usr/bin/env python3

import configparser
import os

class Bunch(object):
    def __init__(self, adict):
        for key, value in adict.items():
            setattr(self, key, value)


class Params(object):

    def __init__(self, ini):
        # Parse INI file
        if not os.path.isfile(ini):
            print("CFG file", ini, "not found!")
            exit(-1)
        config = configparser.ConfigParser()
        config.optionxform = str
        config.read(ini)
        self.fpga_config = config["FPGA"]
        self.fpga_config_calc = dict()
        self.tech_config_dict = dict()
        self.src_dict   = dict()

        # get relevant tech data
        self.tmp_tech_config = config[eval(self.fpga_config["TARGET_TECHNOLOGY"])]

        for key,val in self.tmp_tech_config.items():
            if (val[0] == '"') or (val[0] == '['):
                exec(key.upper() + " = eval(val)")
                exec("self.tech_config_dict[\"" + key.upper() + "\"] = eval(val)")
            else:
                exec(key.upper() + " = int(eval(val))")
                exec("self.tech_config_dict[\"" + key.upper() + "\"] = int(eval(val))")
        self.tech_config = Bunch(self.tech_config_dict)

        # get relevant src data
        self.tmp_src_config = config["SOURCES"]

        for key,val in self.tmp_src_config.items():
            exec(key.upper() + " = eval(val)")
            exec("self.src_dict[\"" + key.upper() + "\"] = eval(val)")
        self.src = Bunch(self.src_dict)

        for key,val in self.fpga_config.items():
            if (val[0] == '"'):
                exec("self." + key.upper() + " = eval(val)")
                exec("self.fpga_config_calc[\"" + key.upper() + "\"] = val")
            else:
                # hacky way to get int values for calculated config vals in locals first
                exec(key.upper() + " = int(eval(val))")
                # save values to class for export
                exec("self." + key.upper() + " = int(eval(val))")
                exec("self.fpga_config_calc[\"" + key.upper() + "\"] = int(eval(val))")


# Called only if executed directly
def main():
    # Parse command-line arguments
    parser = argparse.ArgumentParser(description="Tool to generate FPGA parameters files for RTL & verification flow")
    parser.add_argument("--cfg", type=str, help="Input parameters cfg file", default="../arch/params.cfg")
    parser.add_argument("--vhd", type=str, help="RTL config file (VHDL)", default="../rtl/fpga_params_pkg.vhd")
    parser.add_argument("--tcl", type=str, help="TCL config file", default="")
    parser.add_argument("--vtr", type=str, help="VTR arch config file (XML)", default="../arch/vtr/arch.xml")
    args = parser.parse_args()

    # Parse input config
    p = Params(args.cfg)

    # Generate VHDL parameters file
    constants = ""
    for key,val in p.fpga_config.items():
        if ("<<" in val) or (">>" in val):
            raise ValueError("Shifts are not supported!")
        if (val[0] == '"'):
            ctype = "string "
        else:
            ctype = "integer"
        constants += "constant " + key.upper() + " "*(20-len(key)) + " : " + ctype + " := " + val + ";\n"

    print(FPGA_PARAMS_FMT.format(constants=constants, name="fpga_params_pkg", cfg=args.cfg), file=open(args.vhd, "w"))

    # Generate TCL parameters file
    if (args.tcl != ""):
        constants = ""
        for key,val in p.fpga_config_calc.items():
            constants += "set " + key.upper() + " " + str(val) + "\n"

        print(constants, file=open(args.tcl, "w"))

    # Generate crossbar
    lb_crossbar = ""
    for i in range(p.BLOCK_CROSS_MUXES):
        cell = (i // p.FPGA_LUT_WIDTH)
        inputs = ""
        cells = ""
        for j in range(p.CELLS_PER_BLOCK):
            if (cell != j):
                cells += LB_CROSSBAR_CELL_FMT.format(j=j)
        for j in range((i % p.FPGA_LUT_WIDTH)*p.LBCROSS_INPUTS, (((i % p.FPGA_LUT_WIDTH)+1)*p.LBCROSS_INPUTS)):
            inputs += LB_CROSSBAR_IN_FMT.format(j=j)
        lb_crossbar += LB_CROSSBAR_FMT.format(i=i, cell=cell, i_mod=(i % p.FPGA_LUT_WIDTH), inputs=inputs, cells=cells, DELAY=p.tech_config.TECH_LBCROSS_DELAY)

    # Calc delays
        lut_delay_matrix = ""
        for i in range(p.FPGA_LUT_WIDTH):
            lut_delay = p.tech_config.TECH_LUT_DELAY
            if i >=2:   # !only for SKY130!
                lut_delay *= 2
            # lut_delay_matrix += "                {PS}e-12\n".format(PS=(i+2)*p.tech_config.TECH_LUT_DELAY)
            lut_delay_matrix += "                {PS}e-12\n".format(PS=(i+2)*lut_delay)

    # Generate VTR config file (XML) !!!! TODO : generate XML with large memory !!!!
    print(VTR_PARAMS_FMT.format(cfg=args.cfg, **p.fpga_config_calc, **p.tech_config_dict, MEMORY_NAME = "mem_"+str(p.MEMORY_SIZE)+"x"+str(p.MEMORY_WIDTH),
        CELLS_PER_BLOCK_1=(p.CELLS_PER_BLOCK-1), MEMORY_DEPTH_P1=(p.MEMORY_DEPTH+1), M0=(p.MEMORY_WIDTH-1), M1=(p.MEMORY_DEPTH+p.MEMORY_WIDTH),
        M2=(p.MEMORY_DEPTH+2), M3=(p.MEMORY_DEPTH+p.MEMORY_WIDTH+p.MEMORY_WIDTH), M4=(p.MEMORY_DEPTH+p.MEMORY_WIDTH+1),
        BLK_INPUT_FRAC=(1 / p.BLOCK_IN_MUXES_COEF), lb_crossbar=lb_crossbar, LUT_DELAY_MATRIX=lut_delay_matrix,
        TECH_RNODE_RSEG_DELAY=(p.tech_config.TECH_RSEGM_DELAY+p.tech_config.TECH_RNODE_DELAY)), file=open(args.vtr, "w"))

# Parameters files templates
FPGA_PARAMS_FMT = r''' -- Generated from {cfg} parameters file

package {name} is

{constants}

end {name};

package body {name} is
end {name};
'''

LB_CROSSBAR_IN_FMT = r'''fpga_logic_block.logic_i[{j}] '''
LB_CROSSBAR_CELL_FMT = r'''fpga_logic_cell[{j}].out '''
LB_CROSSBAR_FMT = r'''<mux name="crossbar_{i}" input="{cells} {inputs}" output="fpga_logic_cell[{cell}].in[{i_mod}]">
            <delay_constant max="{DELAY}e-12" in_port="{inputs}" out_port="fpga_logic_cell[{cell}].in[{i_mod}]"/> <!-- block_in_mux included not here but in ipin_cblock -->
            <delay_constant max="{DELAY}e-12" in_port="{cells}" out_port="fpga_logic_cell[{cell}].in[{i_mod}]"/>
        </mux>
        '''
VTR_PARAMS_FMT = r'''<!--
Generated from {cfg} parameters file
--><architecture>

  <models>
      <model name="fpga_memory">
      <input_ports>
        <port name="clk_i" is_clock="1"/>
        <port name="ce_a_i" clock="clk_i"/>
        <port name="we_b_i" clock="clk_i"/>
        <port name="addr_a_i" clock="clk_i"/>
        <port name="addr_b_i" clock="clk_i"/>
        <port name="data_b_i" clock="clk_i"/>
      </input_ports>
      <output_ports>
        <port name="data_a_o" clock="clk_i"/>
      </output_ports>
    </model>
  </models>
  <!-- ODIN II specific config ends -->

  <!-- Physical descriptions begin -->
  <layout>
    <fixed_layout name="fpga_layout" width="{FPGA_FABRIC_SIZE_X}" height="{FPGA_FABRIC_SIZE_Y}">
        <!--Perimeter of 'io' blocks with 'EMPTY' blocks at corners-->
        <perimeter type="io" priority="100"/>
        <corners type="EMPTY" priority="101"/>
        <!--Fill with 'fpga_logic_block'-->
        <fill type="fpga_logic_block" priority="10"/>
        <col type="fpga_memory_blck" startx="{MEMORY_STARTX}" starty="1" repeatx="{MEMORY_REPEATX}" priority="20"/> <!-- !! ugly name to be similar in length to fpga_logic_block !! -->
    </fixed_layout>
  </layout>
  <device>
    <sizing R_minW_nmos="4220.930176" R_minW_pmos="11207.599609"/>
    <area grid_logic_tile_area="2229.320068"/>
    <chan_width_distr>
      <x distr="uniform" peak="1.000000"/>
      <y distr="uniform" peak="1.000000"/>
    </chan_width_distr>
    <switch_block type="wilton" fs="3"/>
    <connection_block input_switch_name="ipin_cblock"/>
  </device>
  <switchlist>
    <switch type="mux" name="0" R="0" Cout="0." Cin="0.000000e+00" Tdel="{TECH_RNODE_RSEG_DELAY}e-12" mux_trans_size="1" buf_size="auto"/>
    <switch type="mux" name="ipin_cblock" R="0" Cout="0." Cin="0.000000e+00" Tdel="{TECH_BINPUT_DELAY}e-12" mux_trans_size="1" buf_size="auto"/>
  </switchlist>
  <segmentlist>
    <segment freq="1.000000" length="1" type="unidir" Rmetal="0.000000" Cmetal="0.000000e+00">
    <mux name="0"/>
    <sb type="pattern">1 1</sb>
    <cb type="pattern">1</cb>
    </segment>
  </segmentlist>

  <complexblocklist>

    <!-- Define I/O pads begin -->
    <!-- Capacity is a unique property of I/Os, it is the maximum number of I/Os that can be placed at the same (X,Y) location on the FPGA -->
    <pb_type name="io" capacity="{PINS_PER_PAD}">
      <input name="outpad" num_pins="1"/>
      <output name="inpad" num_pins="1"/>
      <clock name="clock" num_pins="1"/>

      <!-- IOs can operate as either inputs or outputs. -->
      <mode name="inpad">
        <pb_type name="inpad" blif_model=".input" num_pb="1">
          <output name="inpad" num_pins="1"/>
        </pb_type>
        <interconnect>
          <direct name="inpad" input="inpad.inpad" output="io.inpad">
            <delay_constant max="{TECH_IOIN_DELAY}e-12" in_port="inpad.inpad" out_port="io.inpad"/>
          </direct>
        </interconnect>

      </mode>
      <mode name="outpad">
        <pb_type name="outpad" blif_model=".output" num_pb="1">
          <input name="outpad" num_pins="1"/>
        </pb_type>
        <interconnect>
          <direct name="outpad" input="io.outpad" output="outpad.outpad">
            <delay_constant max="{TECH_IOOUT_DELAY}e-12" in_port="io.outpad" out_port="outpad.outpad"/>
          </direct>
        </interconnect>
      </mode>

      <!-- Every input pin is driven by 15% of the tracks in a channel, every output pin is driven by 10% of the tracks in a channel -->
      <fc in_type="frac" in_val="{BLK_INPUT_FRAC}" out_type="frac" out_val="0.125"/>

      <!-- IOs go on the periphery of the FPGA, for consistency,
          make it physically equivalent on all sides so that only one definition of I/Os is needed.
          If I do not make a physically equivalent definition, then I need to define 4 different I/Os, one for each side of the FPGA
        -->
      <pinlocations pattern="custom">
        <loc side="left">io.outpad io.inpad io.clock</loc>
        <loc side="top">io.outpad io.inpad io.clock</loc>
        <loc side="right">io.outpad io.inpad io.clock</loc>
        <loc side="bottom">io.outpad io.inpad io.clock</loc>
      </pinlocations>

      <!-- Place I/Os on the sides of the FPGA -->
      <power method="ignore"/>
    </pb_type>
    <!-- Define I/O pads ends -->

    <!-- Define general purpose logic block (CLB) begin -->
    <pb_type name="fpga_logic_block">
      <input name="logic_i" num_pins="{BLOCK_INPUTS}" equivalent="none"/>   <!-- ?equivalent? -->
      <output name="logic_o" num_pins="{BLOCK_OUTPUTS}" equivalent="none"/>
      <clock name="clk" num_pins="1"/>

      <!-- Describe basic logic element. -->
      <pb_type name="fpga_logic_cell" num_pb="{CELLS_PER_BLOCK}">
        <input name="in" num_pins="{CELL_INPUTS}"/>
        <output name="out" num_pins="1"/>
        <clock name="clk" num_pins="1"/>
        <!-- LUT mode definition begin -->
        <mode name="n1_lut4">
            <!-- Define LUT -->
            <pb_type name="fpga_lut" blif_model=".names" num_pb="1" class="lut">
              <input name="in" num_pins="{FPGA_LUT_WIDTH}" port_class="lut_in"/>
              <output name="out" num_pins="1" port_class="lut_out"/>
              <!-- LUT timing using delay matrix -->
              <delay_matrix type="max" in_port="fpga_lut.in" out_port="fpga_lut.out">
{LUT_DELAY_MATRIX}
              </delay_matrix>
            </pb_type>

            <!-- Define flip-flop -->
            <pb_type name="fpga_register" blif_model=".latch" num_pb="1" class="flipflop">
              <input name="D" num_pins="1" port_class="D"/>
              <output name="Q" num_pins="1" port_class="Q"/>
              <clock name="clk" num_pins="1" port_class="clock"/>
              <T_setup value="{TECH_REG_SETUP}e-12" port="fpga_register.D" clock="clk"/>
              <T_clock_to_Q max="{TECH_REG_CLK2Q}e-12" port="fpga_register.Q" clock="clk"/>
            </pb_type>

            <interconnect>
              <direct name="direct1" input="fpga_logic_cell.in" output="fpga_lut[0].in"/>
              <direct name="direct2" input="fpga_lut.out" output="fpga_register.D">
                <!-- Advanced user option that tells CAD tool to find LUT+FF pairs in netlist -->
                <pack_pattern name="ble" in_port="fpga_lut.out" out_port="fpga_register.D"/>
              </direct>
              <direct name="direct3" input="fpga_logic_cell.clk" output="fpga_register.clk"/>
              <mux name="mux1" input="fpga_register.Q fpga_lut.out" output="fpga_logic_cell.out">
                <delay_constant max="{TECH_LBOUT_DELAY}e-12" in_port="fpga_register.Q fpga_lut.out" out_port="fpga_logic_cell.out"/>
              </mux>
            </interconnect>
        </mode>
        <!-- 4-LUT mode definition end -->
      </pb_type>
      <interconnect>
        <!-- LUT commutation MUX -->
        {lb_crossbar}
        <complete name="clks" input="fpga_logic_block.clk" output="fpga_logic_cell[{CELLS_PER_BLOCK_1}:0].clk">
        </complete>
        <direct name="clbouts1" input="fpga_logic_cell[{CELLS_PER_BLOCK_1}:0].out" output="fpga_logic_block.logic_o">
            <!-- ??probably where is a better place for LB -> routing node delay somewhere?? -->
            <delay_constant max="{TECH_BOUTPUT_DELAY}e-12" in_port="fpga_logic_cell[{CELLS_PER_BLOCK_1}:0].out" out_port="fpga_logic_block.logic_o"/>
        </direct>
      </interconnect>

      <!-- Every input pin is driven by 1/BLOCK_IN_MUXES_COEF of the tracks in a channel, every output pin is driven by 100% of the tracks in a channel -->
      <fc in_type="frac" in_val="{BLK_INPUT_FRAC}" out_type="frac" out_val="1"/>

      <pinlocations pattern="spread"/>

      <!-- Place this general purpose logic block in any unspecified column -->
      </pb_type>
    <!-- Define general purpose logic block (CLB) ends -->

    <pb_type name="fpga_memory_blck" height="1">
        <clock name="clk_i" num_pins="1"/>

        <input name="logic_i" num_pins="{BLOCK_INPUTS}"/>
        <output name="logic_o" num_pins="{BLOCK_OUTPUTS}"/>

        <mode name="{MEMORY_NAME}">
            <pb_type name="{MEMORY_NAME}" blif_model=".subckt fpga_memory" num_pb="1">
                <clock name="clk_i" num_pins="1" port_class="clock"/>

                <input name="ce_a_i" num_pins="1" port_class="write_en"/>
                <input name="addr_a_i" num_pins="{MEMORY_DEPTH}" port_class="address1"/>
                <output name="data_a_o" num_pins="{MEMORY_WIDTH}" port_class="data_out1"/>

                <input name="we_b_i" num_pins="1" port_class="write_en2"/>
                <input name="addr_b_i" num_pins="{MEMORY_DEPTH}" port_class="address2"/>
                <input name="data_b_i" num_pins="{MEMORY_WIDTH}" port_class="data_in2"/>

                <T_setup value="2.448e-10" port="{MEMORY_NAME}.addr_a_i" clock="clk_i"/>
                <T_clock_to_Q max="2.448e-10" port="{MEMORY_NAME}.data_a_o" clock="clk_i"/>
                <T_setup value="1.852e-9" port="{MEMORY_NAME}.ce_a_i" clock="clk_i"/>

                <T_setup value="1.852e-9" port="{MEMORY_NAME}.addr_b_i" clock="clk_i"/>
                <T_setup value="1.852e-9" port="{MEMORY_NAME}.data_b_i" clock="clk_i"/>
                <T_setup value="1.852e-9" port="{MEMORY_NAME}.we_b_i" clock="clk_i"/>
            </pb_type>
            <interconnect>
                <direct name="ce_a_i" input="fpga_memory_blck.logic_i[0]" output="{MEMORY_NAME}.ce_a_i"/>
                <direct name="addr_a_i" input="fpga_memory_blck.logic_i[{MEMORY_DEPTH}:1]" output="{MEMORY_NAME}.addr_a_i"/>
                <direct name="data_a_o" input="{MEMORY_NAME}.data_a_o[{M0}:0]" output="fpga_memory_blck.logic_o"/>

                <direct name="we_b_i" input="fpga_memory_blck.logic_i[{MEMORY_DEPTH_P1}]" output="{MEMORY_NAME}.we_b_i"/>
                <direct name="addr_b_i" input="fpga_memory_blck.logic_i[{M1}:{M2}]" output="{MEMORY_NAME}.addr_b_i"/>
                <direct name="data_b_i" input="fpga_memory_blck.logic_i[{M3}:{M4}]" output="{MEMORY_NAME}.data_b_i"/>

                <direct name="clk_i" input="fpga_memory_blck.clk_i" output="{MEMORY_NAME}.clk_i"/>
            </interconnect>
        </mode>

        <fc in_type="frac" in_val="{BLK_INPUT_FRAC}" out_type="frac" out_val="1"/>
        <pinlocations pattern="spread"/>
    </pb_type>

  </complexblocklist>
</architecture>

'''


# Do not call main when importing this module
if __name__ == "__main__":
    # import sys
    import argparse
    main()
