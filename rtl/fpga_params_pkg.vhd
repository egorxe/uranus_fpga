 -- Generated from ../arch/params.cfg parameters file

package fpga_params_pkg is

constant FPGA_FABRIC_SIZE_X   : integer := 4;
constant FPGA_FABRIC_SIZE_Y   : integer := 9;
constant FPGA_LUT_WIDTH       : integer := 4;
constant FPGA_LUT_SIZE        : integer := (2**FPGA_LUT_WIDTH);
constant CELL_INPUTS          : integer := FPGA_LUT_WIDTH;
constant CELL_OUTPUTS         : integer := 1;
constant CELLS_PER_BLOCK      : integer := 8;
constant BLOCK_INPUTS         : integer := (CELLS_PER_BLOCK * CELL_INPUTS);
constant BLOCK_OUTPUTS        : integer := (CELLS_PER_BLOCK * CELL_OUTPUTS);
constant LOGIC_BLOCKS         : integer := (FPGA_FABRIC_SIZE_X-2)*(FPGA_FABRIC_SIZE_Y-2);
constant FABRIC_BLOCKS_X      : integer := FPGA_FABRIC_SIZE_X-2;
constant FABRIC_BLOCKS_Y      : integer := FPGA_FABRIC_SIZE_Y-2;
constant FABRIC_VROUTE_X      : integer := FPGA_FABRIC_SIZE_X-1;
constant FABRIC_VROUTE_Y      : integer := FPGA_FABRIC_SIZE_Y-2;
constant FABRIC_HROUTE_X      : integer := FPGA_FABRIC_SIZE_X-2;
constant FABRIC_HROUTE_Y      : integer := FPGA_FABRIC_SIZE_Y-1;
constant TRACKS_PER_RNODE     : integer := 16;
constant TOTAL_TRACKS         : integer := (TRACKS_PER_RNODE * 2);
constant BLOCK_SIDES          : integer := 4;
constant MUX_PER_CLASS        : integer := 1;
constant BLOCK_OUT_PERSIDE    : integer := (BLOCK_OUTPUTS / BLOCK_SIDES);
constant BLOCK_IN_PERSIDE     : integer := (BLOCK_INPUTS / BLOCK_SIDES);
constant BLOCK_L_MUX_START    : integer := 0;
constant BLOCK_R_MUX_START    : integer := (BLOCK_L_MUX_START+BLOCK_OUT_PERSIDE);
constant FORWARD_MUX_START    : integer := (BLOCK_R_MUX_START+BLOCK_OUT_PERSIDE);
constant LEFT_MUX_START       : integer := (FORWARD_MUX_START+MUX_PER_CLASS);
constant RIGHT_MUX_START      : integer := (LEFT_MUX_START+MUX_PER_CLASS);
constant CELL_LUT_MUX_START   : integer := 0;
constant CELL_IN_MUX_START    : integer := (CELL_LUT_MUX_START+CELLS_PER_BLOCK);
constant BLK_MUX_UP_START     : integer := 0;
constant BLK_MUX_DOWN_START   : integer := TRACKS_PER_RNODE;
constant BLK_MUX_LEFT_START   : integer := 0;
constant BLK_MUX_RIGHT_START  : integer := TRACKS_PER_RNODE;
constant BLOCK_CROSS_MUXES    : integer := (CELL_INPUTS*CELLS_PER_BLOCK);
constant LBCROSS_INPUTS       : integer := (BLOCK_INPUTS / FPGA_LUT_WIDTH);
constant LBCROSS_MUX_STATE_WDT : integer := 4;
constant BLOCK_IN_MUXES_COEF  : integer := 8;
constant BLOCK_INPUTS_MUXES   : integer := (TOTAL_TRACKS / BLOCK_IN_MUXES_COEF);
constant BINPUT_MUX_STATE_WDT : integer := 2;
constant RNODE_MUX_STATE_WDT  : integer := 3;
constant RNODE_INPUTS         : integer := (3 + BLOCK_OUT_PERSIDE*2);
constant MEMORY_STARTX        : integer := 400;
constant MEMORY_REPEATX       : integer := 5;
constant MEMORY_SIZE_X        : integer := 1;
constant MEMORY_SIZE_Y        : integer := 1;
constant MEMORY_WIDTH         : integer := 8;
constant MEMORY_DEPTH         : integer := 7;
constant MEMORY_SIZE          : integer := 2**MEMORY_DEPTH;
constant FABRIC_IO_PADS       : integer := (FPGA_FABRIC_SIZE_X+FPGA_FABRIC_SIZE_Y)*2 - 8;
constant PINS_PER_PAD         : integer := 8;
constant FABRIC_IO            : integer := FABRIC_IO_PADS * PINS_PER_PAD;
constant LEFT_IO              : integer := (FPGA_FABRIC_SIZE_Y-2) * PINS_PER_PAD;
constant UP_IO                : integer := (FPGA_FABRIC_SIZE_X-2) * PINS_PER_PAD;
constant RIGHT_IO             : integer := (FPGA_FABRIC_SIZE_Y-2) * PINS_PER_PAD;
constant DOWN_IO              : integer := (FPGA_FABRIC_SIZE_X-2) * PINS_PER_PAD;
constant LEFT_IO_START        : integer := 0;
constant UP_IO_START          : integer := (LEFT_IO_START + LEFT_IO);
constant RIGHT_IO_START       : integer := (UP_IO_START + UP_IO);
constant DOWN_IO_START        : integer := (RIGHT_IO_START + RIGHT_IO);
constant LEFT_IO_END          : integer := (LEFT_IO);
constant UP_IO_END            : integer := (LEFT_IO_END + UP_IO);
constant RIGHT_IO_END         : integer := (UP_IO_END + RIGHT_IO);
constant DOWN_IO_END          : integer := (RIGHT_IO_END + DOWN_IO);
constant MAX_IO_PINS          : integer := FABRIC_IO;
constant CELL_CONFIG_SIZE     : integer := (FPGA_LUT_SIZE + 1);
constant BLKMUX_CONFIG_SIZE   : integer := (BLOCK_CROSS_MUXES*LBCROSS_MUX_STATE_WDT);
constant BLOCK_CONFIG_SIZE    : integer := ((CELL_CONFIG_SIZE*CELLS_PER_BLOCK) + BLKMUX_CONFIG_SIZE);
constant RNODE_CONFIG_SIZE    : integer := (RNODE_MUX_STATE_WDT * TRACKS_PER_RNODE);
constant BLOCK_CFGCHAIN_LEN   : integer := (BLOCK_CONFIG_SIZE + BINPUT_MUX_STATE_WDT*BLOCK_INPUTS)*FABRIC_BLOCKS_Y;
constant VRNODE_CFGCHAIN_LEN  : integer := (BINPUT_MUX_STATE_WDT*2*PINS_PER_PAD + FABRIC_VROUTE_X * RNODE_CONFIG_SIZE * 2);
constant HRNODE_CFGCHAIN_LEN  : integer := (BINPUT_MUX_STATE_WDT*2*PINS_PER_PAD + FABRIC_HROUTE_Y * RNODE_CONFIG_SIZE * 2);
constant CONFIG_CHAINS_BLOCK  : integer := FABRIC_BLOCKS_X;
constant CONFIG_CHAINS_HRNODE : integer := FABRIC_HROUTE_X;
constant CONFIG_CHAINS_VRNODE : integer := FABRIC_VROUTE_Y;
constant TARGET_TECHNOLOGY    : string  := "ASIC_GF_180C";


end fpga_params_pkg;

package body fpga_params_pkg is
end fpga_params_pkg;

