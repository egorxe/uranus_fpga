library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_logic_cell is
    port (
        config_i    : cell_config_type;

        clk_i       : in  std_logic;
        glb_rstn_i  : in  std_logic;

        logic_i     : in  cells_logic_in_type;
        logic_o     : out std_logic
    );
end fpga_logic_cell;

architecture arch of fpga_logic_cell is

constant zero_register_config : register_config_type := ('1', '0');

signal lut_out      : std_logic;
signal register_out : std_logic;

signal logic_in_buf : cells_logic_in_type;

begin

IN_BUFS : for i in 0 to CELL_INPUTS-1 generate
    cell_tstart  : fpga_tech_buffer port map (logic_i(i), logic_in_buf(i));
end generate;

lut : entity fpgalib.fpga_lut
    generic map (
        LUT_WIDTH => FPGA_LUT_WIDTH
    )
    port map (
        glb_rstn_i  => glb_rstn_i,
        config_i    => config_i.lut_config,

        logic_i     => logic_in_buf,
        logic_o     => lut_out
    );

cell_reg : fpga_tech_register
    port map (
        clk_i    => clk_i,
        rstn_i   => glb_rstn_i,
        --config_i => zero_register_config, --config_i.reg_config,
        config_i_rst_polarity   => '0',
        config_i_rst_value      => '0',
        data_i   => lut_out,
        data_o   => register_out
    );

-- MUX
logic_o <= lut_out when (config_i.mux_config = '0') and (glb_rstn_i = '1') else register_out;

end arch;
