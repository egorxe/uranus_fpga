library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_fabric is
    generic (
        FABRIC_X        : integer := FABRIC_X;
        FABRIC_Y        : integer := FABRIC_Y;
        FABRIC_INPUTS   : integer := FABRIC_IO;
        FABRIC_OUTPUTS  : integer := FABRIC_IO
    );
    port (
        -- Clock & global reset
        clk_i           : in  std_logic;
        glb_rst_i       : in  std_logic;

        -- Config signals
        
        config_block_i  : in sr_to_fpga_config_array_type(CONFIG_CHAINS_BLOCK-1 downto 0);
        config_block_o  : out sr_from_fpga_config_array_type(CONFIG_CHAINS_BLOCK-1 downto 0);
        
        config_vrnode_i : in sr_to_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
        config_vrnode_o : out sr_from_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
        
        config_hrnode_i : in sr_to_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);
        config_hrnode_o : out sr_from_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);                

        inputs_i        : in  std_logic_vector(FABRIC_INPUTS-1 downto 0);
        outputs_o       : out std_logic_vector(FABRIC_OUTPUTS-1 downto 0)
    );
end fpga_fabric;

architecture arch of fpga_fabric is

------------------------------------------------------------------------
-- Routing types
------------------------------------------------------------------------
--type block_in_array is array (1 to FABRIC_BLOCKS_X, 1 to FABRIC_BLOCKS_Y) of std_logic_vector(BLOCK_INPUTS-1 downto 0);     -- 1-based to reflect real geometry
type block_out_array is array (1 to FABRIC_BLOCKS_X, 1 to FABRIC_BLOCKS_Y) of std_logic_vector(BLOCK_OUTPUTS-1 downto 0);    -- 1-based to reflect real geometry

type v_tracks_in_array is array (0 to FABRIC_VROUTE_X-1, 1 to FABRIC_VROUTE_Y) of rnode_tracks_array;
type v_tracks_out_array is array (0 to FABRIC_VROUTE_X-1, 1 to FABRIC_VROUTE_Y) of std_logic_vector(TRACKS_PER_RNODE-1 downto 0);
type h_tracks_in_array is array (1 to FABRIC_HROUTE_X, 0 to FABRIC_HROUTE_Y-1) of rnode_tracks_array;
type h_tracks_out_array is array (1 to FABRIC_HROUTE_X, 0 to FABRIC_HROUTE_Y-1) of std_logic_vector(TRACKS_PER_RNODE-1 downto 0);

------------------------------------------------------------------------
-- Config types
------------------------------------------------------------------------
constant RNODE_CONFIG_CHAIN_LEN_H :   integer := (FABRIC_Y-2)*2+5;    -- +2 for IO muxes +1 for output
constant RNODE_CONFIG_CHAIN_LEN_V :   integer := (FABRIC_X-2)*2+5;    -- +2 for IO muxes +1 for output
type block_cfg_shift_chain_array is array (0 to CONFIG_CHAINS_BLOCK-1) of std_logic_vector(FABRIC_BLOCKS_Y downto 0); -- +1 for output
type hrnode_cfg_shift_chain_array is array (0 to CONFIG_CHAINS_HRNODE-1) of std_logic_vector(RNODE_CONFIG_CHAIN_LEN_H-1 downto 0); 
type vrnode_cfg_shift_chain_array is array (0 to CONFIG_CHAINS_VRNODE-1) of std_logic_vector(RNODE_CONFIG_CHAIN_LEN_V-1 downto 0);

------------------------------------------------------------------------
-- Block signals
------------------------------------------------------------------------
--signal block_in         : block_in_array;
signal block_out        : block_out_array;

------------------------------------------------------------------------
-- Config signals
------------------------------------------------------------------------
signal glb_rstn                 : std_logic;
signal block_cfg_shift_chain    : block_cfg_shift_chain_array;
signal hrnode_cfg_shift_chain   : hrnode_cfg_shift_chain_array;
signal vrnode_cfg_shift_chain   : vrnode_cfg_shift_chain_array;

------------------------------------------------------------------------
-- Routing signals
------------------------------------------------------------------------
signal up_tracks_in     : v_tracks_in_array;
signal up_tracks_out    : v_tracks_out_array;
signal down_tracks_in   : v_tracks_in_array;
signal down_tracks_out  : v_tracks_out_array;
signal left_tracks_in   : h_tracks_in_array;
signal left_tracks_out  : h_tracks_out_array;
signal right_tracks_in  : h_tracks_in_array;
signal right_tracks_out : h_tracks_out_array;

signal up_tracks_fwd    : v_tracks_out_array;
signal down_tracks_fwd  : v_tracks_out_array;
signal left_tracks_fwd  : h_tracks_out_array;
signal right_tracks_fwd : h_tracks_out_array;

------------------------------------------------------------------------
-- Functions
------------------------------------------------------------------------

-- Patch track number overflow
function TrackNum(i : integer) return integer is
    variable res : integer;
begin
    if (i >= TRACKS_PER_RNODE) then
        res := i - TRACKS_PER_RNODE;
    elsif (i < 0) then
        res := i + TRACKS_PER_RNODE;
    else
        res := i;
    end if;

    assert (res >= 0) and (res < TRACKS_PER_RNODE) report "Wrong track num" severity failure;

    return res;
end;

-- Calc block output number from side
function GetBlockOutput(dir : direction_type; block_outputs : std_logic_vector) return std_logic_vector is
    variable first : integer;
    variable res : std_logic_vector(BLOCK_OUT_PERSIDE-1 downto 0);
begin
    case (dir) is
        when DIR_UP =>
            first := 0;
        when DIR_RIGHT =>
            first := 1;
        when DIR_DOWN =>
            first := 2;
        when DIR_LEFT =>
            first := 3;
    end case;

    for i in 0 to BLOCK_OUT_PERSIDE-1 loop
        res(i) := block_outputs(first + i*BLOCK_SIDES);
    end loop;

    return res;
end;

-- Form IO signals to be like block outputs
function IoInFrm(s : std_logic_vector; x : integer; y : integer; t : integer) return std_logic_vector is
begin
    --return ExtVec(s(XYtoIOl(x,y) downto XYtoIOr(x,y)), BLOCK_OUT_PERSIDE);
    -- !! hardcoded for PIN_PER_PAD=8 !!
    return ExtVec(s(XYtoIOr(x,y)+t/2), BLOCK_OUT_PERSIDE);
    --return s(XYtoIOr(x,y)+t/4+1) & s(XYtoIOr(x,y)+t/4);
end;


begin

------------------------------------------------------------------------
-- Some assert checks
------------------------------------------------------------------------
--assert (PINS_PER_PAD = 1) report "Only single pin per pad is supported!" severity failure;
assert (PINS_PER_PAD = BLOCK_IN_PERSIDE) report "Pins per pad should equal to BLOCK_IN_PERSIDE!" severity failure;
assert (BLOCK_INPUTS_MUXES*BLOCK_IN_MUXES_COEF/2 = TRACKS_PER_RNODE) severity failure;

assert (BLOCK_CONFIG_SIZE = BLOCK_CONFIG_TYPE_SIZE) report "Config size mismatch!" severity failure;
assert (RNODE_CONFIG_SIZE = ROUTE_NODE_CONFIG_TYPE_SIZE) report "Config size mismatch!" severity failure;

------------------------------------------------------------------------
-- Reset
------------------------------------------------------------------------
glb_rstn <= not glb_rst_i;

------------------------------------------------------------------------
-- Structure blocks & their input muxes
------------------------------------------------------------------------
STRUCT_BLOCKS_X : for x in 1 to FABRIC_BLOCKS_X generate
    STRUCT_BLOCKS_Y : for y in 1 to FABRIC_BLOCKS_Y generate

        -- Structure block
        struct_block : fpga_struct_block
        --generic map (
            --POS_X   => x,
            --POS_Y   => y
        --)
        port map (
            clk_i       => clk_i,
            glb_rstn_i  => glb_rstn,

            -- Config signals
            config_clk_i    => config_block_i(x-1).clk,
            config_ena_i    => glb_rst_i,
            config_shift_i  => block_cfg_shift_chain(x-1)(y),
            config_shift_o  => block_cfg_shift_chain(x-1)(y-1),

            -- Track inputs
            inputs_up_i     => (right_tracks_out(x, y) & left_tracks_out(x, y)),
            inputs_right_i  => (down_tracks_out(x, y) & up_tracks_out(x, y)),
            inputs_down_i   => (right_tracks_out(x, y-1) & left_tracks_out(x, y-1)),
            inputs_left_i   => (down_tracks_out(x-1, y) & up_tracks_out(x-1, y)),
            outputs_o       => block_out(x, y)
        );

    end generate;

    block_cfg_shift_chain(x-1)(FABRIC_BLOCKS_Y) <= config_block_i(x-1).sda;
    config_block_o(x-1).sda <= block_cfg_shift_chain(x-1)(0);
end generate;


------------------------------------------------------------------------
-- Vertical routing network
------------------------------------------------------------------------
VERTICAL_ROUTING_NETWORK_X : for x in 0 to FABRIC_X-2 generate 
    VERTICAL_ROUTING_NETWORK_Y : for y in 1 to FABRIC_Y-2 generate

        CFG_CONN : if (x = 0) generate
            vrnode_cfg_shift_chain(y-1)(0) <= config_vrnode_i(y-1).sda;   
            config_vrnode_o(y-1).sda <= vrnode_cfg_shift_chain(y-1)(RNODE_CONFIG_CHAIN_LEN_V-1);
        end generate;

        -- intermidiate signals to check for edges
        UP_FWD_NONEDGE : if (y /= 1) generate
            up_tracks_fwd(x, y) <= up_tracks_out(x, y-1);
        end generate;
        UP_FWD_EDGE : if (y = 1) generate
            up_tracks_fwd(x, y) <= (others => '0');
        end generate;
        DOWN_FWD_NONEDGE : if (y /= FABRIC_Y-2) generate
            down_tracks_fwd(x, y) <= down_tracks_out(x, y+1);
        end generate;
        DOWN_FWD_EDGE : if (y = FABRIC_Y-2) generate
            down_tracks_fwd(x, y) <= (others => '0');
        end generate;

        -- Going UP, extend all fields to unified width
        LEFT_IO: if (x = 0) generate
            -- left IO out
            routing_left_io : entity fpgalib.fpga_io_mux
            port map (
                config_clk_i    => config_vrnode_i(y-1).clk,
                config_ena_i    => glb_rst_i,
                config_shift_i  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+3),
                config_shift_o  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+4),

                route_i     => (down_tracks_out(x, y) & up_tracks_out(x, y)), 
                pins_o      => outputs_o(XYtoIOl(x,y) downto XYtoIOr(x,y))
            );

            -- left IO in
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                up_tracks_in(x, y)(t) <= left_tracks_out(x+1, y-1)(TrackNum(t+1)) & '0'
                    & up_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_LEFT, block_out(x+1, y)) & IoInFrm(inputs_i, x, y, t);
                down_tracks_in(x,y)(t) <= '0' & left_tracks_out(x+1,y)(TrackNum(TRACKS_PER_RNODE-2-t))
                    & down_tracks_fwd(x,y)(t) & GetBlockOutput(DIR_LEFT, block_out(x+1, y)) & IoInFrm(inputs_i, x, y, t);
            end generate;

        end generate;

        UP_DOWN_TRACKS: if (x /= 0) and (x /= FABRIC_X-2) generate
            -- Nonedge routing
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                up_tracks_in(x, y)(t) <= left_tracks_out(x+1,y-1)(TrackNum(t+1)) & right_tracks_out(x, y-1)(TrackNum(0-t))
                    & up_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_LEFT, block_out(x+1, y)) & GetBlockOutput(DIR_RIGHT, block_out(x, y));
                down_tracks_in(x, y)(t) <= right_tracks_out(x, y)(TrackNum(t+1)) & left_tracks_out(x+1, y)(TrackNum(TRACKS_PER_RNODE-2-t))
                    & down_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_LEFT, block_out(x+1, y)) & GetBlockOutput(DIR_RIGHT, block_out(x, y));
            end generate;
        end generate;

        routing_node_up : fpga_routing_node_wcfg
        port map (
            config_clk_i    => config_vrnode_i(y-1).clk,
            config_ena_i    => glb_rst_i,
            config_shift_i  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+2),
            config_shift_o  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+3),

            route_i     => up_tracks_in(x, y),
            route_o     => up_tracks_out(x, y)
        );

        -- Going DOWN, extend all fields to unified width
        RIGHT_IO : if (x = FABRIC_X-2) generate
            -- right IO out
            routing_right_io : entity fpgalib.fpga_io_mux
            port map (
                config_clk_i    => config_vrnode_i(y-1).clk,
                config_ena_i    => glb_rst_i,
                config_shift_i  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2),    -- 0 in chain
                config_shift_o  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+1),

                route_i     => (down_tracks_out(x, y) & up_tracks_out(x, y)), 
                pins_o      => outputs_o(XYtoIOl(x+1,y) downto XYtoIOr(x+1,y))
            );

            -- right IO in
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                up_tracks_in(x, y)(t) <= '0' & right_tracks_out(x, y-1)(TrackNum(0-t))
                    & up_tracks_fwd(x, y)(t) & IoInFrm(inputs_i, x+1, y, t) & GetBlockOutput(DIR_RIGHT, block_out(x, y));
                down_tracks_in(x, y)(t) <= right_tracks_out(x, y)(TrackNum(t+1)) & '0'
                    & down_tracks_fwd(x, y)(t) & IoInFrm(inputs_i, x+1, y, t) & GetBlockOutput(DIR_RIGHT, block_out(x, y));
            end generate;
        end generate;

        routing_node_down : fpga_routing_node_wcfg
        port map (
            config_clk_i    => config_vrnode_i(y-1).clk,
            config_ena_i    => glb_rst_i,
            config_shift_i  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+1),
            config_shift_o  => vrnode_cfg_shift_chain(y-1)((FABRIC_VROUTE_X-x-1)*2+2),

            route_i     => down_tracks_in(x, y),
            route_o     => down_tracks_out(x, y)
        );

    end generate;
end generate;


------------------------------------------------------------------------
-- Horizontal routing network
------------------------------------------------------------------------
HORIZONTAL_ROUTING_NETWORK_X : for x in 1 to FABRIC_X-2 generate

    hrnode_cfg_shift_chain(x-1)(0) <= config_hrnode_i(x-1).sda;   
    config_hrnode_o(x-1).sda <= hrnode_cfg_shift_chain(x-1)(RNODE_CONFIG_CHAIN_LEN_H-1);

    HORIZONTAL_ROUTING_NETWORK_Y : for y in 0 to FABRIC_Y-2 generate

        -- intermidiate signals to check for edges
        LEFT_FWD_NONEDGE : if (x /= FABRIC_X-2) generate
            left_tracks_fwd(x, y) <= left_tracks_out(x+1, y);
        end generate;
        LEFT_FWD_EDGE : if (x = FABRIC_X-2) generate
            left_tracks_fwd(x, y) <= (others => '0');
        end generate;
        RIGHT_FWD_NONEDGE : if (x /= 1) generate
            right_tracks_fwd(x, y) <= right_tracks_out(x-1, y);
        end generate;
        RIGHT_FWD_EDGE : if (x = 1) generate
            right_tracks_fwd(x, y) <= (others => '0');
        end generate;

        -- Going LEFT, extend all fields to unified width
        DOWN_IO: if (y = 0) generate
            -- down IO out
            routing_down_io : entity fpgalib.fpga_io_mux
            port map (
                config_clk_i    => config_hrnode_i(x-1).clk,
                config_ena_i    => glb_rst_i,
                config_shift_i  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+3),
                config_shift_o  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+4),

                route_i     => (right_tracks_out(x, y) & left_tracks_out(x, y)),
                pins_o      => outputs_o(XYtoIOl(x,y) downto XYtoIOr(x,y))
            );

            -- down IO in
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                left_tracks_in(x, y)(t) <= down_tracks_out(x, y+1)(TrackNum(0-t)) & "0"
                    & left_tracks_fwd(x, y)(t) & IoInFrm(inputs_i, x, y, t) & GetBlockOutput(DIR_DOWN, block_out(x, y+1));
                right_tracks_in(x, y)(t) <= "0" & down_tracks_out(x-1, y+1)(TrackNum(t-1))
                    & right_tracks_fwd(x, y)(t) & IoInFrm(inputs_i, x, y, t) & GetBlockOutput(DIR_DOWN, block_out(x, y+1));
            end generate;
        end generate;

        LEFT_RIGHT_TRACKS : if (y /= 0) and (y /= FABRIC_Y-2) generate
            -- Nonedge routing
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                left_tracks_in(x, y)(t) <= down_tracks_out(x, y+1)(TrackNum(0-t)) & up_tracks_out(x, y)(TrackNum(t-1))
                    & left_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_UP, block_out(x, y)) & GetBlockOutput(DIR_DOWN, block_out(x, y+1));
                right_tracks_in(x, y)(t) <= up_tracks_out(x-1, y)(TrackNum(TRACKS_PER_RNODE-2-t)) & down_tracks_out(x-1, y+1)(TrackNum(t-1))
                    & right_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_UP, block_out(x, y)) & GetBlockOutput(DIR_DOWN, block_out(x, y+1));
            end generate;
        end generate;

        routing_node_left : fpga_routing_node_wcfg
        port map (
            config_clk_i    => config_hrnode_i(x-1).clk,
            config_ena_i    => glb_rst_i,
            config_shift_i  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+2),
            config_shift_o  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+3),

            route_i     => left_tracks_in(x, y),
            route_o     => left_tracks_out(x, y)
        );

        -- Going RIGHT, extend all fields to unified width
        UP_IO : if (y = FABRIC_Y-2) generate
            -- up io in
            TRACK : for t in 0 to TRACKS_PER_RNODE-1 generate
                left_tracks_in(x, y)(t) <= "0" & up_tracks_out(x, y)(TrackNum(t-1))
                    & left_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_UP, block_out(x, y)) & IoInFrm(inputs_i, x, y+1, t);
                right_tracks_in(x, y)(t) <= up_tracks_out(x-1, y)(TrackNum(TRACKS_PER_RNODE-2-t)) & "0"
                    & right_tracks_fwd(x, y)(t) & GetBlockOutput(DIR_UP, block_out(x, y)) & IoInFrm(inputs_i, x, y+1, t);
            end generate;

            -- up IO out
            routing_up_io : entity fpgalib.fpga_io_mux
            port map (
                config_clk_i    => config_hrnode_i(x-1).clk,
                config_ena_i    => glb_rst_i,
                config_shift_i  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2),    -- 0 in chain
                config_shift_o  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+1),

                route_i     => (right_tracks_out(x, y) & left_tracks_out(x, y)), 
                pins_o      => outputs_o(XYtoIOl(x,y+1) downto XYtoIOr(x,y+1))
            );
        end generate;

        routing_node_right : fpga_routing_node_wcfg
        port map (
            config_clk_i    => config_hrnode_i(x-1).clk,
            config_ena_i    => glb_rst_i,
            config_shift_i  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+1),
            config_shift_o  => hrnode_cfg_shift_chain(x-1)((FABRIC_HROUTE_Y-y-1)*2+2),

            route_i     => right_tracks_in(x, y),
            route_o     => right_tracks_out(x, y)
        );

    end generate;
end generate;

end arch;
