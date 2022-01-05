-- Test project of wishbone counter for FPGA testing with Caravel & cocotb

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    
entity wb_cnt is
    generic (
        CNT_LIM : integer := 127;
        WB_ADDR : std_logic_vector(31 downto 0) := X"30F0_00F0"
    );
    port (
        wb_clk_i        : in std_logic;
        wb_rst_i        : in std_logic;
        wbs_stb_i       : in std_logic;
        wbs_cyc_i       : in std_logic;
        wbs_we_i        : in std_logic;
        wbs_dat_i       : in std_logic_vector(31 downto 0);
        wbs_adr_i       : in std_logic_vector(31 downto 0);
        wbs_ack_o       : out std_logic;
        wbs_dat_o       : out std_logic_vector(31 downto 0)
    );
end wb_cnt;

architecture behav of wb_cnt is
signal cnt : integer range 0 to CNT_LIM;
begin

wbs_dat_o <= std_logic_vector(to_unsigned(cnt, 32));

SYNC : process (wb_clk_i) is
begin
    if rising_edge(wb_clk_i) then
        if wb_rst_i = '1' then
            cnt <= 0;
            wbs_ack_o <= '0';
        else
            wbs_ack_o <= '1';
            if wbs_cyc_i = '1' and wbs_stb_i = '1' and wbs_ack_o = '1' and wbs_adr_i = WB_ADDR then
                if wbs_we_i = '1' then
                    if cnt = CNT_LIM then
                        cnt <= 0;
                    else
                        cnt <= cnt + 1;
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;
    
end behav;
