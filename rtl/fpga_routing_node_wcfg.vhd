library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_routing_node_wcfg is
    port (
        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        route_i     : rnode_tracks_array;
        route_o     : out std_logic_vector(TRACKS_PER_RNODE-1 downto 0)
    );
end fpga_routing_node_wcfg;

architecture arch of fpga_routing_node_wcfg is

component fpga_routing_node is  -- component declaration needed for blackbox in synthesis
    port (
        -- Config signals
        config_data_i   : in  std_logic_vector(ROUTE_NODE_CONFIG_TYPE_SIZE-1 downto 0);

        -- Routing signals
        route_i         : in  rnode_tracks_array;
        route_o         : out std_logic_vector(TRACKS_PER_RNODE-1 downto 0)
    );
end component;

signal config_data          : std_logic_vector(ROUTE_NODE_CONFIG_TYPE_SIZE-1 downto 0);
signal config_data_gated    : std_logic_vector(ROUTE_NODE_CONFIG_TYPE_SIZE-1 downto 0);

begin

CFG_NOZERO_ONLOAD : if (not ZERO_CFG_WHILE_LOAD) generate
    config_data_gated <= config_data;
end generate;
CFG_ZERO_ONLOAD : if ZERO_CFG_WHILE_LOAD generate
    config_data_gated <= config_data when config_ena_i = '0' else (others => '0');
end generate;

node : fpga_routing_node
    port map (
        config_data_i    => config_data_gated,

        -- Routing signals
        route_i     => route_i,
        route_o     => route_o
    );

-- Config registers
config_register : entity fpgalib.fpga_cfg_shiftreg
    generic map (
        CONFIG_WDT  => ROUTE_NODE_CONFIG_TYPE_SIZE
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
