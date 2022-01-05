library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_io_mux is
    port (
        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Routing to IO pins
        route_i         : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        pins_o          : out std_logic_vector(PINS_PER_PAD-1 downto 0)
    );
end fpga_io_mux;

architecture arch of fpga_io_mux is

signal config_chain : std_logic_vector(PINS_PER_PAD downto 0);

begin

config_chain(PINS_PER_PAD) <= config_shift_i;
config_shift_o <= config_chain(0);

MUXES : for i in 0 to PINS_PER_PAD-1 generate
    io_mux : entity fpgalib.fpga_routing_mux_wcfg
        generic map (
            CFG_WDT => BINPUT_MUX_STATE_WDT,
            INPUTS  => BLOCK_INPUTS_MUXES
        )
        port map (
            config_clk_i    => config_clk_i,
            config_ena_i    => config_ena_i,
            config_shift_i  => config_chain(PINS_PER_PAD-i),
            config_shift_o  => config_chain(PINS_PER_PAD-i-1),
    
            route_i     => BlkInputReduction(route_i, i),
            route_o     => pins_o(i)
        );
end generate;

end arch;
