-- Simple syncronus Wishbone arbiter

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio;

use std.textio.all;

library fpgalib;
    use fpgalib.wishbone_pkg.all;
    
entity wb_arbiter_sync is
    generic(
        ABN_CNT                     : integer := 8
        );
    port (        
        wb_clk_i                    : in std_logic;
        wb_rst_i                    : in std_logic;
    
        wb_i_up                     : in wb_mosi_type;
        wb_o_up                     : out wb_miso_type;
        
        addr_map                    : in addr32_array_type(ABN_CNT - 1 downto 0); -- list of base addresses. If you need singe addr in range, put it as a base
        
        wb_i_bottom                 : in wb_miso_array_type(ABN_CNT - 1 downto 0);
        wb_o_bottom                 : out wb_mosi_array_type(ABN_CNT - 1 downto 0)
    );
end wb_arbiter_sync;

architecture behav of wb_arbiter_sync is
type state_type is (IDLE, REQUEST);
signal state : state_type;
signal wb_i_up_buf : wb_mosi_type;
begin

SYNC : process (wb_clk_i, wb_rst_i)
variable pn_buf : integer range 0 to ABN_CNT - 1;
begin
    if wb_rst_i = '1' then
        for i in 0 to ABN_CNT - 1 loop
            wb_o_bottom(i) <= WB_MOSI_STUB;
            wb_o_up <= WB_MISO_STUB;
        end loop;
        state <= IDLE;
    else
        if rising_edge(wb_clk_i) then
            case state is
                when IDLE =>
                    wb_o_up <= WB_MISO_STUB;
                    if wb_i_up.cyc_i = '1' and wb_i_up.stb_i = '1' and wb_o_up.ack_o = '0' then
                        state <= REQUEST;
                        wb_i_up_buf <= wb_i_up;
                        for i in 0 to ABN_CNT - 1 loop
                            if wb_i_up.adr_i >= addr_map(i) then
                                pn_buf := i;
                            end if;
                        end loop;
                        wb_o_bottom(pn_buf) <= wb_i_up;          
                    end if;
                when REQUEST =>
                    if wb_i_bottom(pn_buf).ack_o = '1' then
                        wb_o_bottom(pn_buf) <= WB_MOSI_STUB;
                        state <= IDLE;
                        wb_o_up.dat_o <= wb_i_bottom(pn_buf).dat_o;
                        wb_o_up.ack_o <= '1';
                    end if;
            end case;
        end if;
    end if;
end process;

end behav;
