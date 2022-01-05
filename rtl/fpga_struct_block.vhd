library ieee;
    use ieee.std_logic_1164.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_struct_block is
    --generic (
        --POS_X           : integer := 1;
        --POS_Y           : integer := 1;
        --BLOCK_INPUTS    : integer := BLOCK_INPUTS;
        --BLOCK_OUTPUTS   : integer := BLOCK_OUTPUTS
    --);
    port (
        clk_i       : in  std_logic;
        glb_rstn_i  : in  std_logic;

        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Connections to routing fabric
        inputs_up_i     : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_right_i  : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_down_i   : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_left_i   : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        outputs_o       : out std_logic_vector(BLOCK_OUTPUTS-1 downto 0)
    );
end fpga_struct_block;

architecture arch of fpga_struct_block is

constant POS_X           : integer := 1;
constant POS_Y           : integer := 1;
--constant BLOCK_INPUTS    : integer := BLOCK_INPUTS;
--constant BLOCK_OUTPUTS   : integer := BLOCK_OUTPUTS;

signal cfg_shift_chain : std_logic_vector(BLOCK_INPUTS+1 downto 0); -- +1 for output

signal block_in     : std_logic_vector(BLOCK_INPUTS-1 downto 0);

begin

--assert (IsMemoryBlock(POS_X, POS_Y) or IsLogicBlock(POS_X, POS_Y))
assert (IsLogicBlock(POS_X, POS_Y) or IsMemoryBlock(POS_X, POS_Y))
report "Incorrect block type at " & ToString(POS_X) & ":" & ToString(POS_Y)
severity failure;

cfg_shift_chain(0) <= config_shift_i;

-- Block input muxes for 4 sides, directions here from logic block perspective
-- config chain goes from "bottom" up
MUXES_UP : for i in 0 to BLOCK_IN_PERSIDE-1 generate
    block_in_mux : entity fpgalib.fpga_routing_mux_wcfg
    generic map (
        CFG_WDT => BINPUT_MUX_STATE_WDT,
        INPUTS  => BLOCK_INPUTS_MUXES     -- mux each input from one side (two directions)
    )
    port map (
        config_clk_i    => config_clk_i,
        config_ena_i    => config_ena_i,
        config_shift_i  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4)))+1),
        config_shift_o  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4)))+2),

        route_i     => BlkInputReduction(inputs_up_i, i),
        route_o     => block_in(i*4)
    );
end generate;
MUXES_RIGHT : for i in 0 to BLOCK_IN_PERSIDE-1 generate
    block_in_mux : entity fpgalib.fpga_routing_mux_wcfg
    generic map (
        CFG_WDT => BINPUT_MUX_STATE_WDT,
        INPUTS  => BLOCK_INPUTS_MUXES     -- mux each input from one side (two directions)
    )
    port map (
        config_clk_i    => config_clk_i,
        config_ena_i    => config_ena_i,
        config_shift_i  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+1)))+1),
        config_shift_o  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+1)))+2),

        route_i     => BlkInputReduction(inputs_right_i, i),
        route_o     => block_in(i*4+1)
    );
end generate;
MUXES_DOWN : for i in 0 to BLOCK_IN_PERSIDE-1 generate
    block_in_mux : entity fpgalib.fpga_routing_mux_wcfg
    generic map (
        CFG_WDT => BINPUT_MUX_STATE_WDT,
        INPUTS  => BLOCK_INPUTS_MUXES     -- mux each input from one side (two directions)
    )
    port map (
        config_clk_i    => config_clk_i,
        config_ena_i    => config_ena_i,
        config_shift_i  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+2)))+1),
        config_shift_o  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+2)))+2),

        route_i     => BlkInputReduction(inputs_down_i, i),
        route_o     => block_in(i*4+2)
    );
end generate;
MUXES_LEFT : for i in 0 to BLOCK_IN_PERSIDE-1 generate
    block_in_mux : entity fpgalib.fpga_routing_mux_wcfg
    generic map (
        CFG_WDT => BINPUT_MUX_STATE_WDT,
        INPUTS  => BLOCK_INPUTS_MUXES     -- mux each input from one side (two directions)
    )
    port map (
        config_clk_i    => config_clk_i,
        config_ena_i    => config_ena_i,
        config_shift_i  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+3)))+1),
        config_shift_o  => cfg_shift_chain(((BLOCK_INPUTS-1-(i*4+3)))+2),

        route_i     => BlkInputReduction(inputs_left_i, i),
        route_o     => block_in(i*4+3)
    );
end generate;


LOGIC : if IsLogicBlock(POS_X, POS_Y) generate
    -- Put logic block here
    logic_block : fpga_logic_block
        port map (
            clk_i       => clk_i,
            glb_rstn_i  => glb_rstn_i,

            -- Config signals
            config_clk_i    => config_clk_i,
            config_ena_i    => config_ena_i,
            config_shift_i  => cfg_shift_chain(0),
            config_shift_o  => cfg_shift_chain(1),

            inputs_i        => block_in,
            outputs_o       => outputs_o
        );

end generate;


--MEMORY : if IsMemoryBlockStart(POS_X, POS_Y) generate
    ---- Put memory block here
    --mem_block : entity fpgalib.fpga_memory_block
        --port map (
            --clk_i       => clk_i,
            --glb_rstn_i   => glb_rstn_i,

            ---- Config signals
            --config_clk_i    => config_clk_i,
            --config_ena_i    => config_ena_i,
            --config_shift_i  => cfg_shift_chain(0),
            --config_shift_o  => cfg_shift_chain(1),

            --inputs_i        => block_in,
            --outputs_o       => outputs_o
        --);

--end generate;

config_shift_o <= cfg_shift_chain(BLOCK_INPUTS+1);

end arch;
