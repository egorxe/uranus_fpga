library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_logic_block is
    port (
        -- Clock & reset
        clk_i           : in  std_logic;
        glb_rstn_i      : in  std_logic;

        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Logic signals
        inputs_i        : in  std_logic_vector(BLOCK_INPUTS-1 downto 0);
        outputs_o       : out std_logic_vector(BLOCK_OUTPUTS-1 downto 0)
    );
end fpga_logic_block;

architecture arch of fpga_logic_block is

function CfgRegToBlockConfig(c : std_logic_vector) return block_config_type is
    variable res : block_config_type;
    constant CELL_CFG_START : integer := BLOCK_CROSS_MUXES*LBCROSS_MUX_STATE_WDT;
begin
    -- pragma translate_off
    -- check config size sanity
    assert (c'length = CELL_CFG_START + (FPGA_LUT_SIZE+1)*CELLS_PER_BLOCK) report "Incorrect config register size! " & integer'image(c'length) severity failure;
    -- pragma translate_on

    for i in 0 to BLOCK_CROSS_MUXES-1 loop
        res.crossbar_config(i) := c(((i+1)*LBCROSS_MUX_STATE_WDT)-1 downto i*LBCROSS_MUX_STATE_WDT);
    end loop;
    for i in 0 to CELLS_PER_BLOCK-1 loop
        res.cell_config(i).lut_config := c((i*CELL_CONFIG_TYPE_SIZE + CELL_CFG_START + FPGA_LUT_SIZE)-1 downto i*CELL_CONFIG_TYPE_SIZE + CELL_CFG_START);
        res.cell_config(i).mux_config := c(i*CELL_CONFIG_TYPE_SIZE + CELL_CFG_START + FPGA_LUT_SIZE);
    end loop;

    return res;
end;

type cells_in_array is array (0 to CELLS_PER_BLOCK-1) of cells_logic_in_type;
type config_array is array (0 to CELLS_PER_BLOCK-1) of cell_config_type;

signal cell_in      : cells_in_array;
signal cell_out     : std_logic_vector(CELLS_PER_BLOCK-1 downto 0);

signal config_data 	: std_logic_vector(BLOCK_CONFIG_TYPE_SIZE-1 downto 0);
signal config_record: block_config_type;

begin

CFG_NOZERO_ONLOAD : if (not ZERO_CFG_WHILE_LOAD) generate
    config_record <= CfgRegToBlockConfig(config_data);
end generate;
CFG_ZERO_ONLOAD : if (ZERO_CFG_WHILE_LOAD) generate
    config_record <= CfgRegToBlockConfig(config_data) when config_ena_i = '0' else block_config_zero;
end generate;


LOGIC_CELLS : for i in 0 to CELLS_PER_BLOCK-1 generate

    cell : entity fpgalib.fpga_logic_cell
    port map (
        config_i    => config_record.cell_config(i),

        clk_i       => clk_i,
        glb_rstn_i  => glb_rstn_i,

        logic_i     => cell_in(i),
        logic_o     => cell_out(i)
    );

end generate;

-- Each LUT input has different block input sources + all other LUT outputs
CROSSBAR : for i in 0 to BLOCK_CROSS_MUXES-1 generate

    crossbar_mux : entity fpgalib.fpga_routing_mux
    generic map (
        INPUTS  => (CELLS_PER_BLOCK + LBCROSS_INPUTS),
        CFG_WDT => LBCROSS_MUX_STATE_WDT,
        GND_IN  => (i / FPGA_LUT_WIDTH)
    )
    port map (
        config_i    => config_record.crossbar_config(i),

        route_i     => inputs_i((((i mod FPGA_LUT_WIDTH)+1)*LBCROSS_INPUTS)-1 downto (i mod FPGA_LUT_WIDTH)*LBCROSS_INPUTS) & cell_out,
        route_o     => cell_in(i / FPGA_LUT_WIDTH)(i mod FPGA_LUT_WIDTH)
    );

end generate;

outputs_o <= cell_out;

-- Config registers
config_register : entity fpgalib.fpga_cfg_shiftreg
    generic map (
        CONFIG_WDT  => BLOCK_CONFIG_TYPE_SIZE
    )
    port map (
        -- Clock & enable
        config_clk_i    => config_clk_i,
        config_ena_i    => config_ena_i,

        -- Shift input & output
        config_shift_i  => config_shift_i,
        config_shift_o  => config_shift_o,

        -- Loaded config data
        config_o        => config_data
    );

end arch;
