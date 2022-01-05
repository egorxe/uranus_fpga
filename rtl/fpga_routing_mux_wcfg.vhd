library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;

entity fpga_routing_mux_wcfg is
    generic (
        INPUTS      : integer := 4;
        CFG_WDT     : integer := 2;
        GND_IN      : integer := -1
    );
    port (
         -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Logic
        route_i     : in  std_logic_vector(INPUTS-1 downto 0);
        route_o     : out std_logic
    );
end fpga_routing_mux_wcfg;

architecture arch of fpga_routing_mux_wcfg is

signal config_data :  std_logic_vector(CFG_WDT-1 downto 0);

begin

-- MUX itself
mux : entity fpgalib.fpga_routing_mux
    generic map (
        INPUTS      => INPUTS,
        CFG_WDT     => CFG_WDT,
        GND_IN      => GND_IN
    )
    port map (
         -- Config signals
        config_i    => config_data,

        -- Logic
        route_i     => route_i,
        route_o     => route_o
    );

-- Config registers
config_register : entity fpgalib.fpga_cfg_shiftreg
    generic map (
        CONFIG_WDT  => CFG_WDT
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
