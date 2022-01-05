-- Test project of wishbone memory for FPGA testing with Caravel & cocotb

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    
entity wb_mem is
    generic (
        MEM_WIDTH : integer := 32;
        MEM_DEPTH : integer := 2 --log2
    );
    port (
        wb_clk_i        : in std_logic;
        wb_rst_i        : in std_logic;
        wbs_stb_i       : in std_logic;
        wbs_cyc_i       : in std_logic;
        wbs_we_i        : in std_logic;
        wbs_dat_i       : in std_logic_vector(MEM_WIDTH - 1 downto 0);
        wbs_adr_i       : in std_logic_vector(MEM_DEPTH - 1 downto 0);
        wbs_ack_o       : out std_logic;
        wbs_dat_o       : out std_logic_vector(MEM_WIDTH - 1 downto 0)
    );
end wb_mem;

architecture behav of wb_mem is
type mem_type is array (2**MEM_DEPTH - 1 downto 0) of std_logic_vector(MEM_WIDTH - 1 downto 0);
signal mem : mem_type;
begin

SYNC : process (wb_clk_i) is
begin
    if rising_edge(wb_clk_i) then
        wbs_ack_o <= '0';
        if wbs_cyc_i = '1' then
            wbs_ack_o <= '1';
            if wbs_we_i = '1' then
                mem(to_integer(unsigned(wbs_adr_i))) <= wbs_dat_i;
            else
                wbs_dat_o <= mem(to_integer(unsigned(wbs_adr_i)));
            end if;
        end if;
    end if;
end process;
    
end behav;
