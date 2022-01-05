-- Test project of wishbone pinout tester for FPGA testing with Caravel & cocotb

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    
entity wb_pins is
    generic (
        PINCOUNT : integer := 38;
        WB_ADDR : std_logic_vector(31 downto 0) := X"30F0_0000"
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
        wbs_dat_o       : out std_logic_vector(31 downto 0);
        
        user_irq        : out std_logic_vector(2 downto 0);
        io_in           : in std_logic_vector(PINCOUNT - 1 downto 0);
        io_out          : out std_logic_vector(PINCOUNT - 1 downto 0);
        io_oeb          : out std_logic_vector(PINCOUNT - 1 downto 0)
    );
end wb_pins;

architecture behav of wb_pins is

begin

SYNC : process (wb_clk_i) is
begin
    if rising_edge(wb_clk_i) then
        if wb_rst_i = '1' then
            io_out <= (others => '1');
            io_oeb <= (others => '1');
            wbs_ack_o <= '0';
            wbs_dat_o <= (others => '0');
            user_irq <= (others => '1');
        else
            wbs_ack_o <= '0';
            wbs_dat_o <= (others => '0');
            if wbs_cyc_i = '1' and wbs_stb_i = '1' and wbs_adr_i(31 downto 16) = WB_ADDR(31 downto 16) then
                wbs_ack_o <= '1';
                if wbs_we_i = '1' then
                    if wbs_dat_i(31 downto 30) = "00" then
                        io_out(to_integer(unsigned(wbs_adr_i))) <= wbs_dat_i(0);
                    elsif wbs_dat_i(31 downto 30) = "10" then
                        io_oeb(to_integer(unsigned(wbs_adr_i))) <= wbs_dat_i(0);
                    elsif wbs_dat_i(31 downto 30) = "01" then
                        user_irq(to_integer(unsigned(wbs_adr_i))) <= wbs_dat_i(0);
                    end if;
                else
                    if wbs_adr_i(15) = '0' then
                        wbs_dat_o <= io_in(31 downto 0);
                    else
                        wbs_dat_o(PINCOUNT - 32 - 1 downto 0) <= io_in(PINCOUNT - 1 downto 32);
                    end if;
                end if;
            end if;
        end if;
    end if;
end process;
    
end behav;
