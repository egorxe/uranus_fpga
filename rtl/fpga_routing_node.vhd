library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_routing_node is
    port (
        -- Config signals
        config_data_i   : in  std_logic_vector(ROUTE_NODE_CONFIG_TYPE_SIZE-1 downto 0);

        -- Routing signals
        route_i         : in  rnode_tracks_array;
        route_o         : out std_logic_vector(TRACKS_PER_RNODE-1 downto 0)
    );
end fpga_routing_node;

architecture arch of fpga_routing_node is

signal route_int : std_logic_vector(TRACKS_PER_RNODE-1 downto 0);

signal buffered_in      : rnode_tracks_array;
signal buffered_out0    : std_logic_vector(TRACKS_PER_RNODE-1 downto 0);
signal buffered_out1    : std_logic_vector(TRACKS_PER_RNODE-1 downto 0);

begin

MUXES : for i in 0 to TRACKS_PER_RNODE-1 generate
    BUFS : for j in 0 to RNODE_INPUTS-1 generate
        rnode_in : fpga_tech_buffer port map (route_i(i)(j), buffered_in(i)(j));
    end generate;
    
    routing_node_track : entity fpgalib.fpga_routing_mux
    generic map (
        INPUTS  => RNODE_INPUTS,
        CFG_WDT => RNODE_MUX_STATE_WDT,
        GND_IN  => RNODE_INPUTS
    )
    port map (
        -- Config signals
        config_i    => config_data_i(((i+1)*RNODE_MUX_STATE_WDT)-1 downto i*RNODE_MUX_STATE_WDT),

        -- Routing signals
        route_i     => buffered_in(i),
        route_o     => route_int(i)
    );

    -- this three buffer structure is needed to break loops & constraint paths at the same time in OpenROAD
    rnode_tfinish : fpga_tech_buffer port map (route_int(i), buffered_out0(i));
    loop_breaker  : fpga_tech_buffer port map (buffered_out0(i), buffered_out1(i));
    rnode_tstart  : fpga_tech_buffer port map (buffered_out1(i), route_o(i));
end generate;

end arch;
