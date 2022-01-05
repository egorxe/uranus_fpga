library ieee;
    use ieee.std_logic_1164.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_memory_block is
    generic (
        BLOCK_INPUTS    : integer := BLOCK_INPUTS;
        BLOCK_OUTPUTS   : integer := BLOCK_OUTPUTS
    );
    port (
        clk_i       : in  std_logic;
        glb_rstn_i  : in  std_logic;

        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        inputs_i    : in  std_logic_vector(BLOCK_INPUTS-1 downto 0);
        outputs_o   : out std_logic_vector(BLOCK_OUTPUTS-1 downto 0)
    );
end fpga_memory_block;

architecture arch of fpga_memory_block is

begin

---- Memory instance
--memory_cell : entity fpgalib.fpga_tech_memory
    --generic map (
        --MEMORY_WIDTH    => MEMORY_WIDTH,
        --MEMORY_DEPTH    => MEMORY_DEPTH
    --)
    --port map (
        --clk_i       => clk_i,

        --ce_a_i      => inputs_i(0),
        --addr_a_i    => inputs_i(7 downto 1),
        --data_a_o    => outputs_o,

        --we_b_i      => inputs_i(8),
        --addr_b_i    => inputs_i(15 downto 9),
        --data_b_i    => inputs_i(23 downto 16)
    --);

---- Config registers
--config_register : entity fpgalib.fpga_cfg_shiftreg
    --generic map (
        --CONFIG_WDT  => BLOCK_CONFIG_TYPE_SIZE
    --)
    --port map (
        ---- Clock & enable
        --config_clk_i    => config_clk_i,
        --config_ena_i    => config_ena_i,

        ---- Shift input & output
        --config_shift_i  => config_shift_i,
        --config_shift_o  => config_shift_o,

        ---- Loaded config data
        --config_o        => open
    --);

end arch;
