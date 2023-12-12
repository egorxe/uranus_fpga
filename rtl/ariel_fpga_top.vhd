library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio;

use std.textio.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.wishbone_pkg.all;
    use fpgalib.fpga_params_pkg.all;
    
entity ariel_fpga_top is
    port (
    
        -- Wishbone from caravel --
        wb_clk_i        : in std_logic;
        wb_rst_i        : in std_logic;
        wbs_stb_i       : in std_logic;
        wbs_cyc_i       : in std_logic;
        wbs_we_i        : in std_logic;
        wbs_dat_i       : in std_logic_vector(31 downto 0);
        wbs_adr_i       : in std_logic_vector(31 downto 0);
        wbs_ack_o       : out std_logic;
        wbs_dat_o       : out std_logic_vector(31 downto 0);
        
        -- Caravel logic analyzer --
        la_data_in      : in std_logic_vector(63 downto 0);
        la_data_out     : out std_logic_vector(63 downto 0);
        la_oenb         : in std_logic_vector(63 downto 0);      

        -- 38 User IO --
        io_in           : in std_logic_vector(37 downto 0);
        io_out          : out std_logic_vector(37 downto 0);
        io_oeb          : out std_logic_vector(37 downto 0);
        
        -- Second clock from Caravel PLL --
        user_clock2     : in std_logic;
        
        -- Interrupts --
        user_irq        : out std_logic_vector(2 downto 0)

    );
end ariel_fpga_top;


architecture structural of ariel_fpga_top is

constant STUB : std_logic_vector(255 downto 0) := (others => '0'); -- simple stub for unused inputs

constant BLOCK_CONFIG_DEFAULT_VALUE : std_logic_vector(CONFIG_CHAINS_BLOCK - 1 downto 0) := (others => '0');
constant VRNODE_CONFIG_DEFAULT_VALUE : std_logic_vector(CONFIG_CHAINS_VRNODE - 1 downto 0) := (others => '0');
constant HRNODE_CONFIG_DEFAULT_VALUE : std_logic_vector(CONFIG_CHAINS_HRNODE - 1 downto 0) := (others => '0');
constant TAP_CONFIG_DEFAULT_VALUE : std_logic_vector(2 downto 0) := (others => '0');
constant RST_CONFIG_DEFAULT_VALUE : std_logic_vector(3 downto 0) := "1110";

constant N_UPPER_BOND_PAD : integer := 23;
constant N_LOWER_BOND_PAD : integer := 15;
constant W_UPPER_BOND_PAD : integer := 37;
constant W_LOWER_BOND_PAD : integer := 24;
constant E_UPPER_BOND_PAD : integer := 14;
constant E_LOWER_BOND_PAD : integer := 0;

constant N_PADS_CNT : integer := N_UPPER_BOND_PAD - N_LOWER_BOND_PAD + 1;
constant W_PADS_CNT : integer := W_UPPER_BOND_PAD - W_LOWER_BOND_PAD + 1;
constant E_PADS_CNT : integer := E_UPPER_BOND_PAD - E_LOWER_BOND_PAD + 1;

constant N_UPPER_BOND : integer := UP_IO_END-1;
constant N_LOWER_BOND : integer := UP_IO_START;
constant W_UPPER_BOND : integer := LEFT_IO_END-1;
constant W_LOWER_BOND : integer := LEFT_IO_START;
constant E_UPPER_BOND : integer := RIGHT_IO_END-1;
constant E_LOWER_BOND : integer := RIGHT_IO_START;
constant S_UPPER_BOND : integer := DOWN_IO_END-1;
constant S_LOWER_BOND : integer := DOWN_IO_START;

constant WB_I_WIDTH     : integer := wbs_adr_i'length + wbs_dat_i'length + 3;
constant WB_O_WIDTH     : integer := wbs_dat_o'length + 1;

constant IO_HIGH            : integer := 37;
constant IO_HIGH_FPGA       : integer := IO_HIGH-1;
constant IO_LOW             : integer := 15;
constant IO_CNT             : integer := IO_HIGH_FPGA-IO_LOW+1; -- IO count used in fpga fabric
constant WB_ADDR_WDT        : integer := 8;
constant WB_IN_SIGS         : integer := 32 + WB_ADDR_WDT + 3;
constant WB_OUT_SIGS        : integer := 32 + 1;
constant INPUT_SIG_WDT      : integer := IO_CNT + WB_IN_SIGS + 1; -- +1 because of rst
constant ZERO_CAP           : std_logic_vector(255 downto 0) := (others => '0');

signal block_data                           : std_logic_vector(31 downto 0);
signal block_data_out                       : std_logic_vector(31 downto 0);
signal vrnode_data                          : std_logic_vector(31 downto 0);
signal vrnode_data_out                      : std_logic_vector(31 downto 0);
signal hrnode_data                          : std_logic_vector(31 downto 0);
signal hrnode_data_out                      : std_logic_vector(31 downto 0);
signal fw_tap_bus                           : std_logic_vector(31 downto 0);
signal fpga_rst                             : std_logic_vector(31 downto 0);

signal config_block_clk : std_logic;
signal config_vrnode_clk: std_logic;
signal config_hrnode_clk: std_logic;

signal config_block_i                        : sr_to_fpga_config_array_type(CONFIG_CHAINS_BLOCK-1 downto 0);
signal config_block_o                        : sr_from_fpga_config_array_type(CONFIG_CHAINS_BLOCK-1 downto 0);
signal config_vrnode_i                       : sr_to_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
signal config_vrnode_o                       : sr_from_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
signal config_hrnode_i                       : sr_to_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);
signal config_hrnode_o                       : sr_from_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);  

-- FABRIC_IO = 144 for Ophelia
signal inputs_i                             : std_logic_vector(FABRIC_IO-1 downto 0);
signal outputs_o                            : std_logic_vector(FABRIC_IO-1 downto 0);
signal outputs_o_buf                        : std_logic_vector(FABRIC_IO-1 downto 0);
signal inputs_i_buf                         : std_logic_vector(FABRIC_IO-1 downto 0);
signal io_oeb_buf                           : std_logic_vector(IO_HIGH_FPGA downto IO_LOW);

signal wb_from_caravel                      : wb_mosi_type;
signal wb_to_caravel                        : wb_miso_type;
constant WB_DEV_CNT                         : integer := 7;
signal wb_i_bottom                          : wb_miso_array_type(WB_DEV_CNT - 1 downto 0);
signal wb_o_bottom                          : wb_mosi_array_type(WB_DEV_CNT - 1 downto 0);
constant ADDR_MAP                           : addr32_array_type := (EFUSE_WB_ADDR,
                                                                    FPGA_FABRIC_WB_ADDR,
                                                                    TAP_CONFIG_REGISTER_ADDR,
                                                                    RST_CONFIG_REGISTER_ADDR,
                                                                    HRNODE_CONFIG_REGISTER_ADDR,
                                                                    VRNODE_CONFIG_REGISTER_ADDR,
                                                                    BLOCK_CONFIG_REGISTER_ADDR
                                                                    );
                                                                    
signal fw_wbs_adr_i     : std_logic_vector(31 downto 0); 
signal fw_wbs_dat_i     : std_logic_vector(31 downto 0);
signal fw_wbs_we_i         : std_logic;
signal fw_wbs_stb_i     : std_logic;
signal fw_wbs_cyc_i     : std_logic;
signal self_fw_done     : std_logic;
signal master_wb_select : std_logic;

component efuse_ctrl is
    port (
        wb_rst_i : in std_logic; --! active high reset
        wb_clk_i : in std_logic; --! clock

        -- Wishbone secondary
        wb_adr_i : in std_logic_vector(11 downto 0);      --! address
        wb_dat_o : out std_logic_vector(8 - 1 downto 0);  --! read data
        wb_dat_i : in std_logic_vector(8 - 1 downto 0);   --! write data
        wb_we_i  : in std_logic;                          --! active high WE
        wb_sel_i : in std_logic_vector(8/8 - 1 downto 0); --! not connected
        wb_stb_i : in std_logic; --! WB stb signal
        wb_cyc_i : in std_logic; --! WB cyc signal
        wb_ack_o : out std_logic --! WB ack signal
    );
end component;

component fpga_fw_loader is
    port (
        wb_rst_i : in std_logic; --! active high reset
        wb_clk_i : in std_logic; --! clock
        
        -- Wishbone secondary
        wb_adr_i : out std_logic_vector(31 downto 0); --! address
        wb_dat_o : in std_logic_vector(31 downto 0); --! read data
        wb_dat_i : out std_logic_vector(31 downto 0); --! write data
        wb_we_i : out std_logic; --! active hihg WE
        wb_sel_i : out std_logic_vector(3 downto 0); --! not connected
        wb_stb_i : out std_logic; --! WB stb signal
        wb_cyc_i : out std_logic; --! WB cyc signal
        wb_ack_o : in std_logic; --! WB ack signal
        self_fw_done : out std_logic;
        self_fw_enable : in std_logic
    );
end component;


begin

la_data_out <= (0 => self_fw_done, others=>'0'); 
user_irq <= (others=>'0');   


-- wishbone from caravel mapping into record

wb_from_caravel.stb_i <= wbs_stb_i when master_wb_select = '0' else fw_wbs_stb_i;
wb_from_caravel.cyc_i <= wbs_cyc_i when master_wb_select = '0' else fw_wbs_cyc_i;
wb_from_caravel.we_i <= wbs_we_i   when master_wb_select = '0' else fw_wbs_we_i;
wb_from_caravel.dat_i <= wbs_dat_i when master_wb_select = '0' else fw_wbs_dat_i;
wb_from_caravel.adr_i <= wbs_adr_i when master_wb_select = '0' else fw_wbs_adr_i;
wbs_ack_o <= wb_to_caravel.ack_o when master_wb_select = '0' else '0';
wbs_dat_o <= wb_to_caravel.dat_o;

master_wb_select <= io_in(37) and not(self_fw_done);


fpga_fw_loader_inst : fpga_fw_loader
    port map(
        wb_rst_i => wb_rst_i,
        wb_clk_i => wb_clk_i,
        wb_adr_i => fw_wbs_adr_i,
        wb_dat_o => wb_to_caravel.dat_o,
        wb_dat_i => fw_wbs_dat_i,
        wb_we_i => fw_wbs_we_i,
        wb_sel_i => open,
        wb_stb_i => fw_wbs_stb_i,
        wb_cyc_i => fw_wbs_cyc_i,
        wb_ack_o => wb_to_caravel.ack_o,
        self_fw_done => self_fw_done,
        self_fw_enable => io_in(37)
    );

wb_arbiter_inst : wb_arbiter_sync
    generic map(
        ABN_CNT                     => WB_DEV_CNT
        )
    port map(    
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        
        wb_i_up                     => wb_from_caravel,
        wb_o_up                     => wb_to_caravel,
        
        addr_map                    => ADDR_MAP,
        
        wb_i_bottom                 => wb_i_bottom,
        wb_o_bottom                 => wb_o_bottom
    );

fpga_fabric_inst : entity fpgalib.fpga_fabric
    port map (
        clk_i       => wb_clk_i,
        glb_rst_i   => fpga_rst(0),

        config_block_i        => config_block_i,
        config_block_o        => config_block_o,
        config_vrnode_i        => config_vrnode_i,
        config_vrnode_o        => config_vrnode_o,
        config_hrnode_i        => config_hrnode_i,
        config_hrnode_o        => config_hrnode_o,

        inputs_i            => inputs_i_buf,
        outputs_o           => outputs_o_buf
    );

block_write_fw_reg_inst : entity work.wb_register32
    generic map (ENABLE_REG_I   => True)
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_i                        => wb_o_bottom(0),
        wb_o                        => wb_i_bottom(0),
        reg_o                       => block_data,
        reg_i                       => block_data_out
    );

vrnode_write_fw_reg_inst : entity work.wb_register32
    generic map (ENABLE_REG_I   => True)
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_i                        => wb_o_bottom(1),
        wb_o                        => wb_i_bottom(1),
        reg_o                       => vrnode_data,
        reg_i                       => vrnode_data_out
    );
    
hrnode_write_fw_reg_inst : entity work.wb_register32
    generic map (ENABLE_REG_I   => True)
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_i                        => wb_o_bottom(2),
        wb_o                        => wb_i_bottom(2),
        reg_o                       => hrnode_data,
        reg_i                       => hrnode_data_out
    );    
    
fabric_reset_reg_inst : entity work.wb_register32
    generic map (
        REG_O_DEFAULT_VALUE         => X"0000000E"
    )
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_i                        => wb_o_bottom(3),
        wb_o                        => wb_i_bottom(3),
        reg_o                       => fpga_rst,
        reg_i                       => X"00000000"
    );

tap_write_fw_reg_inst : entity work.wb_register32
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_i                        => wb_o_bottom(4),
        wb_o                        => wb_i_bottom(4),
        reg_o                       => fw_tap_bus,
        reg_i                       => X"00000000"
    );

efuse_mem_inst : efuse_ctrl
    port map (
        wb_clk_i                    => wb_clk_i,
        wb_rst_i                    => wb_rst_i,
        wb_adr_i                    => wb_o_bottom(6).adr_i(11 downto 0),
        wb_dat_i                    => wb_o_bottom(6).dat_i(7 downto 0),
        wb_we_i                     => wb_o_bottom(6).we_i,
        wb_sel_i                    => "0",
        wb_cyc_i                    => wb_o_bottom(6).cyc_i,
        wb_stb_i                    => wb_o_bottom(6).stb_i,
        wb_ack_o                    => wb_i_bottom(6).ack_o,
        wb_dat_o                    => wb_i_bottom(6).dat_o(7 downto 0)
    );
wb_i_bottom(6).dat_o(31 downto 8) <= (others => '0');

-- Buffers to start CTS from
config_block_clk_buf : fpga_tech_clkbuffer port map (fw_tap_bus(0), config_block_clk);
config_vrnode_clk_buf : fpga_tech_clkbuffer port map (fw_tap_bus(1), config_vrnode_clk);
config_hrnode_clk_buf : fpga_tech_clkbuffer port map (fw_tap_bus(2), config_hrnode_clk);

GEN_BLOCKS_CFG_CONNECTION : for i in 0 to CONFIG_CHAINS_BLOCK - 1 generate
begin
    config_block_i(i).clk <= config_block_clk;
    config_block_i(i).sda <= block_data(i);
    block_data_out(i) <= config_block_o(i).sda;
end generate;
block_data_out(31 downto CONFIG_CHAINS_BLOCK) <= (others =>'0');

GEN_VRNODE_CFG_CONNECTION : for i in 0 to CONFIG_CHAINS_VRNODE - 1 generate
begin
    config_vrnode_i(i).clk <= config_vrnode_clk;
    config_vrnode_i(i).sda <= vrnode_data(i);
    vrnode_data_out(i) <= config_vrnode_o(i).sda;
end generate;
vrnode_data_out(31 downto CONFIG_CHAINS_VRNODE) <= (others =>'0');

GEN_HRNODE_CFG_CONNECTION : for i in 0 to CONFIG_CHAINS_HRNODE - 1 generate
begin
    config_hrnode_i(i).clk <= config_hrnode_clk;
    config_hrnode_i(i).sda <= hrnode_data(i);
    hrnode_data_out(i) <= config_hrnode_o(i).sda;
end generate;
hrnode_data_out(31 downto CONFIG_CHAINS_HRNODE) <= (others =>'0');

-- Terminate IO while in reset --
inputs_i_buf <= inputs_i when fpga_rst(1) = '0' else (others => fpga_rst(2));
outputs_o <= outputs_o_buf when fpga_rst(1) = '0' else (others => fpga_rst(2));
io_oeb(37) <= '1';
io_oeb(IO_HIGH_FPGA downto IO_LOW) <= io_oeb_buf when fpga_rst(1) = '0' else (others => '1');
io_oeb(IO_LOW - 1 downto 0) <= (others => '1'); 

PROC : process(all)
begin
    -- IN
    inputs_i <= (others => '0'); -- to make all unconnected inputs constant
    inputs_i(INPUT_SIG_WDT - 1 downto 0) <= io_in(IO_HIGH_FPGA downto IO_LOW)
                --& ZERO_CAP(14 downto 0)
                & fpga_rst(3)
                & wb_o_bottom(5).stb_i
                & wb_o_bottom(5).cyc_i 
                & wb_o_bottom(5).we_i 
                & wb_o_bottom(5).adr_i(WB_ADDR_WDT-1 downto 0) 
                & wb_o_bottom(5).dat_i;
    --inputs_i(FABRIC_IO - 1 downto 32 + 8 + 3 + IO_CNT) <= (others => '0'); -- hack to make unconnected input constant
    wb_i_bottom(5).dat_o <= outputs_o(FABRIC_IO - 2 downto FABRIC_IO - WB_OUT_SIGS);
    wb_i_bottom(5).ack_o <= outputs_o(FABRIC_IO - 1);
    
    -- OEB
    io_oeb_buf(IO_HIGH_FPGA downto IO_LOW) <= outputs_o(WB_IN_SIGS + 2*IO_CNT - 1 downto WB_IN_SIGS + IO_CNT);
    
    -- OUT
    io_out(37) <= '0';
    io_out(IO_HIGH_FPGA downto IO_LOW) <= outputs_o(WB_IN_SIGS + IO_CNT - 1 downto WB_IN_SIGS);
    --io_out(37 downto 15) <= outputs_o(22 downto 0);
    io_out(IO_LOW - 1 downto 0) <= (others => '0'); -- Unused (for caravel pins)
    
end process; 


end structural;
