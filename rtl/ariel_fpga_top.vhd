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
        la_data_in      : in std_logic_vector(127 downto 0);
        la_data_out     : out std_logic_vector(127 downto 0);
        la_oenb         : in std_logic_vector(127 downto 0);      

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

constant WB_I_WIDTH                         : integer := wbs_adr_i'length + wbs_dat_i'length + 3;
constant WB_O_WIDTH                         : integer := wbs_dat_o'length + 1;

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
signal config_vrnode_i                        : sr_to_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
signal config_vrnode_o                        : sr_from_fpga_config_array_type(CONFIG_CHAINS_VRNODE-1 downto 0);
signal config_hrnode_i                        : sr_to_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);
signal config_hrnode_o                        : sr_from_fpga_config_array_type(CONFIG_CHAINS_HRNODE-1 downto 0);  


signal inputs_i                             : std_logic_vector(FABRIC_IO-1 downto 0);
signal outputs_o                            : std_logic_vector(FABRIC_IO-1 downto 0);
signal outputs_o_buf                        : std_logic_vector(FABRIC_IO-1 downto 0);
signal inputs_i_buf                         : std_logic_vector(FABRIC_IO-1 downto 0);

signal wb_from_caravel                      : wb_mosi_type;
signal wb_to_caravel                        : wb_miso_type;
constant WB_DEV_CNT                         : integer := 6;
signal wb_i_bottom                          : wb_miso_array_type(WB_DEV_CNT - 1 downto 0);
signal wb_o_bottom                          : wb_mosi_array_type(WB_DEV_CNT - 1 downto 0);
constant ADDR_MAP                           : addr32_array_type := (FPGA_FABRIC_WB_ADDR,
                                                                    TAP_CONFIG_REGISTER_ADDR,
                                                                    RST_CONFIG_REGISTER_ADDR,
                                                                    HRNODE_CONFIG_REGISTER_ADDR,
                                                                    VRNODE_CONFIG_REGISTER_ADDR,
                                                                    BLOCK_CONFIG_REGISTER_ADDR);
begin

la_data_out <= (others=>'0');   -- !!!!!!!!!!!!!!! temporarily !!!!!!!!!!!

-- wishbone from caravel mapping into record

wb_from_caravel.stb_i <= wbs_stb_i;
wb_from_caravel.cyc_i <= wbs_cyc_i;
wb_from_caravel.we_i <= wbs_we_i;
wb_from_caravel.dat_i <= wbs_dat_i;
wb_from_caravel.adr_i <= wbs_adr_i;
wbs_ack_o <= wb_to_caravel.ack_o;
wbs_dat_o <= wb_to_caravel.dat_o;

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

-- Terminate IO while reset --
inputs_i_buf <= inputs_i when fpga_rst(1) = '0' else (others => fpga_rst(2));
outputs_o <= outputs_o_buf when fpga_rst(1) = '0' else (others => fpga_rst(2));

PROC : process(all)
begin
    inputs_i <= (others => '0'); -- hack to make unconnected input constant
    
    -- =====================================
    --             North
    -- =====================================
    inputs_i(167) <= io_in(15);
    io_out(15) <= outputs_o(166);
    io_oeb(15) <= outputs_o(165);
    inputs_i(159) <= io_in(16);
    io_out(16) <= outputs_o(158);
    io_oeb(16) <= outputs_o(157);
    inputs_i(151) <= io_in(17);
    io_out(17) <= outputs_o(150);
    io_oeb(17) <= outputs_o(149);
    inputs_i(143) <= io_in(18);
    io_out(18) <= outputs_o(142);
    io_oeb(18) <= outputs_o(141);
    inputs_i(135) <= io_in(19);
    io_out(19) <= outputs_o(134);
    io_oeb(19) <= outputs_o(133);
    inputs_i(127) <= io_in(20);
    io_out(20) <= outputs_o(126);
    io_oeb(20) <= outputs_o(125);
    inputs_i(119) <= io_in(21);
    io_out(21) <= outputs_o(118);
    io_oeb(21) <= outputs_o(117);
    inputs_i(111) <= io_in(22);
    io_out(22) <= outputs_o(110);
    io_oeb(22) <= outputs_o(109);
    inputs_i(103) <= io_in(23);
    io_out(23) <= outputs_o(102);
    io_oeb(23) <= outputs_o(101);
    -- =====================================
    --             East
    -- =====================================
    inputs_i(168) <= io_in(0);
    io_out(0) <= outputs_o(169);
    io_oeb(0) <= outputs_o(170);
    inputs_i(173) <= io_in(1);
    io_out(1) <= outputs_o(174);
    io_oeb(1) <= outputs_o(175);
    inputs_i(178) <= io_in(2);
    io_out(2) <= outputs_o(179);
    io_oeb(2) <= outputs_o(180);
    inputs_i(183) <= io_in(3);
    io_out(3) <= outputs_o(184);
    io_oeb(3) <= outputs_o(185);
    inputs_i(188) <= io_in(4);
    io_out(4) <= outputs_o(189);
    io_oeb(4) <= outputs_o(190);
    inputs_i(193) <= io_in(5);
    io_out(5) <= outputs_o(194);
    io_oeb(5) <= outputs_o(195);
    inputs_i(198) <= io_in(6);
    io_out(6) <= outputs_o(199);
    io_oeb(6) <= outputs_o(200);
    inputs_i(203) <= io_in(7);
    io_out(7) <= outputs_o(204);
    io_oeb(7) <= outputs_o(205);
    inputs_i(208) <= io_in(8);
    io_out(8) <= outputs_o(209);
    io_oeb(8) <= outputs_o(210);
    inputs_i(213) <= io_in(9);
    io_out(9) <= outputs_o(214);
    io_oeb(9) <= outputs_o(215);
    inputs_i(218) <= io_in(10);
    io_out(10) <= outputs_o(219);
    io_oeb(10) <= outputs_o(220);
    inputs_i(223) <= io_in(11);
    io_out(11) <= outputs_o(224);
    io_oeb(11) <= outputs_o(225);
    inputs_i(228) <= io_in(12);
    io_out(12) <= outputs_o(229);
    io_oeb(12) <= outputs_o(230);
    inputs_i(233) <= io_in(13);
    io_out(13) <= outputs_o(234);
    io_oeb(13) <= outputs_o(235);
    inputs_i(238) <= io_in(14);
    io_out(14) <= outputs_o(239);
    io_oeb(14) <= outputs_o(240);
    -- =====================================
    --             West
    -- =====================================
    wb_i_bottom(5).dat_o(0) <= outputs_o(31);
    wb_i_bottom(5).dat_o(1) <= outputs_o(30);
    wb_i_bottom(5).dat_o(2) <= outputs_o(29);
    wb_i_bottom(5).dat_o(3) <= outputs_o(28);
    wb_i_bottom(5).dat_o(4) <= outputs_o(27);
    wb_i_bottom(5).dat_o(5) <= outputs_o(26);
    wb_i_bottom(5).dat_o(6) <= outputs_o(25);
    wb_i_bottom(5).dat_o(7) <= outputs_o(24);
    wb_i_bottom(5).dat_o(8) <= outputs_o(23);
    wb_i_bottom(5).dat_o(9) <= outputs_o(22);
    wb_i_bottom(5).dat_o(10) <= outputs_o(21);
    wb_i_bottom(5).dat_o(11) <= outputs_o(20);
    wb_i_bottom(5).dat_o(12) <= outputs_o(19);
    wb_i_bottom(5).dat_o(13) <= outputs_o(18);
    wb_i_bottom(5).dat_o(14) <= outputs_o(17);
    wb_i_bottom(5).dat_o(15) <= outputs_o(16);
    wb_i_bottom(5).dat_o(16) <= outputs_o(15);
    wb_i_bottom(5).dat_o(17) <= outputs_o(14);
    wb_i_bottom(5).dat_o(18) <= outputs_o(13);
    wb_i_bottom(5).dat_o(19) <= outputs_o(12);
    wb_i_bottom(5).dat_o(20) <= outputs_o(11);
    wb_i_bottom(5).dat_o(21) <= outputs_o(10);
    wb_i_bottom(5).dat_o(22) <= outputs_o(9);
    wb_i_bottom(5).dat_o(23) <= outputs_o(8);
    wb_i_bottom(5).dat_o(24) <= outputs_o(7);
    wb_i_bottom(5).dat_o(25) <= outputs_o(6);
    wb_i_bottom(5).dat_o(26) <= outputs_o(5);
    wb_i_bottom(5).dat_o(27) <= outputs_o(4);
    wb_i_bottom(5).dat_o(28) <= outputs_o(3);
    wb_i_bottom(5).dat_o(29) <= outputs_o(2);
    wb_i_bottom(5).dat_o(30) <= outputs_o(1);
    wb_i_bottom(5).dat_o(31) <= outputs_o(0);
    wb_i_bottom(5).ack_o <= outputs_o(32);
    inputs_i(87) <= io_in(24);
    io_out(24) <= outputs_o(86);
    io_oeb(24) <= outputs_o(85);
    inputs_i(84) <= io_in(25);
    io_out(25) <= outputs_o(83);
    io_oeb(25) <= outputs_o(82);
    inputs_i(81) <= io_in(26);
    io_out(26) <= outputs_o(80);
    io_oeb(26) <= outputs_o(79);
    inputs_i(78) <= io_in(27);
    io_out(27) <= outputs_o(77);
    io_oeb(27) <= outputs_o(76);
    inputs_i(75) <= io_in(28);
    io_out(28) <= outputs_o(74);
    io_oeb(28) <= outputs_o(73);
    inputs_i(72) <= io_in(29);
    io_out(29) <= outputs_o(71);
    io_oeb(29) <= outputs_o(70);
    inputs_i(69) <= io_in(30);
    io_out(30) <= outputs_o(68);
    io_oeb(30) <= outputs_o(67);
    inputs_i(66) <= io_in(31);
    io_out(31) <= outputs_o(65);
    io_oeb(31) <= outputs_o(64);
    inputs_i(63) <= io_in(32);
    io_out(32) <= outputs_o(62);
    io_oeb(32) <= outputs_o(61);
    inputs_i(60) <= io_in(33);
    io_out(33) <= outputs_o(59);
    io_oeb(33) <= outputs_o(58);
    inputs_i(57) <= io_in(34);
    io_out(34) <= outputs_o(56);
    io_oeb(34) <= outputs_o(55);
    inputs_i(54) <= io_in(35);
    io_out(35) <= outputs_o(53);
    io_oeb(35) <= outputs_o(52);
    inputs_i(51) <= io_in(36);
    io_out(36) <= outputs_o(50);
    io_oeb(36) <= outputs_o(49);
    inputs_i(48) <= io_in(37);
    io_out(37) <= outputs_o(47);
    io_oeb(37) <= outputs_o(46);
    -- =====================================
    --             South
    -- =====================================
    inputs_i(304) <= wb_o_bottom(5).adr_i(31);
    inputs_i(305) <= wb_o_bottom(5).adr_i(30);
    inputs_i(306) <= wb_o_bottom(5).adr_i(29);
    inputs_i(307) <= wb_o_bottom(5).adr_i(28);
    inputs_i(308) <= wb_o_bottom(5).adr_i(27);
    inputs_i(309) <= wb_o_bottom(5).adr_i(26);
    inputs_i(310) <= wb_o_bottom(5).adr_i(25);
    inputs_i(311) <= wb_o_bottom(5).adr_i(24);
    inputs_i(312) <= wb_o_bottom(5).adr_i(23);
    inputs_i(313) <= wb_o_bottom(5).adr_i(22);
    inputs_i(314) <= wb_o_bottom(5).adr_i(21);
    inputs_i(315) <= wb_o_bottom(5).adr_i(20);
    inputs_i(316) <= wb_o_bottom(5).adr_i(19);
    inputs_i(317) <= wb_o_bottom(5).adr_i(18);
    inputs_i(318) <= wb_o_bottom(5).adr_i(17);
    inputs_i(319) <= wb_o_bottom(5).adr_i(16);
    inputs_i(320) <= wb_o_bottom(5).adr_i(15);
    inputs_i(321) <= wb_o_bottom(5).adr_i(14);
    inputs_i(322) <= wb_o_bottom(5).adr_i(13);
    inputs_i(323) <= wb_o_bottom(5).adr_i(12);
    inputs_i(324) <= wb_o_bottom(5).adr_i(11);
    inputs_i(325) <= wb_o_bottom(5).adr_i(10);
    inputs_i(326) <= wb_o_bottom(5).adr_i(9);
    inputs_i(327) <= wb_o_bottom(5).adr_i(8);
    inputs_i(328) <= wb_o_bottom(5).adr_i(7);
    inputs_i(329) <= wb_o_bottom(5).adr_i(6);
    inputs_i(330) <= wb_o_bottom(5).adr_i(5);
    inputs_i(331) <= wb_o_bottom(5).adr_i(4);
    inputs_i(332) <= wb_o_bottom(5).adr_i(3);
    inputs_i(333) <= wb_o_bottom(5).adr_i(2);
    inputs_i(334) <= wb_o_bottom(5).adr_i(1);
    inputs_i(335) <= wb_o_bottom(5).adr_i(0);
    inputs_i(272) <= wb_o_bottom(5).dat_i(31);
    inputs_i(273) <= wb_o_bottom(5).dat_i(30);
    inputs_i(274) <= wb_o_bottom(5).dat_i(29);
    inputs_i(275) <= wb_o_bottom(5).dat_i(28);
    inputs_i(276) <= wb_o_bottom(5).dat_i(27);
    inputs_i(277) <= wb_o_bottom(5).dat_i(26);
    inputs_i(278) <= wb_o_bottom(5).dat_i(25);
    inputs_i(279) <= wb_o_bottom(5).dat_i(24);
    inputs_i(280) <= wb_o_bottom(5).dat_i(23);
    inputs_i(281) <= wb_o_bottom(5).dat_i(22);
    inputs_i(282) <= wb_o_bottom(5).dat_i(21);
    inputs_i(283) <= wb_o_bottom(5).dat_i(20);
    inputs_i(284) <= wb_o_bottom(5).dat_i(19);
    inputs_i(285) <= wb_o_bottom(5).dat_i(18);
    inputs_i(286) <= wb_o_bottom(5).dat_i(17);
    inputs_i(287) <= wb_o_bottom(5).dat_i(16);
    inputs_i(288) <= wb_o_bottom(5).dat_i(15);
    inputs_i(289) <= wb_o_bottom(5).dat_i(14);
    inputs_i(290) <= wb_o_bottom(5).dat_i(13);
    inputs_i(291) <= wb_o_bottom(5).dat_i(12);
    inputs_i(292) <= wb_o_bottom(5).dat_i(11);
    inputs_i(293) <= wb_o_bottom(5).dat_i(10);
    inputs_i(294) <= wb_o_bottom(5).dat_i(9);
    inputs_i(295) <= wb_o_bottom(5).dat_i(8);
    inputs_i(296) <= wb_o_bottom(5).dat_i(7);
    inputs_i(297) <= wb_o_bottom(5).dat_i(6);
    inputs_i(298) <= wb_o_bottom(5).dat_i(5);
    inputs_i(299) <= wb_o_bottom(5).dat_i(4);
    inputs_i(300) <= wb_o_bottom(5).dat_i(3);
    inputs_i(301) <= wb_o_bottom(5).dat_i(2);
    inputs_i(302) <= wb_o_bottom(5).dat_i(1);
    inputs_i(303) <= wb_o_bottom(5).dat_i(0);
    inputs_i(271) <= wb_o_bottom(5).we_i;
    inputs_i(270) <= wb_o_bottom(5).cyc_i;
    inputs_i(269) <= wb_o_bottom(5).stb_i;
    inputs_i(268) <= fpga_rst(3);
    user_irq(0) <= outputs_o(267);
    user_irq(1) <= outputs_o(266);
    user_irq(2) <= outputs_o(265);



end process; 

end structural;
