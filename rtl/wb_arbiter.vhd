-- Simple Wishbone arbiter

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio;

use std.textio.all;

library fpgalib;
    use fpgalib.wishbone_pkg.all;
    
entity wb_arbiter is
    generic(
        ABN_CNT                     : integer := 8
        );
    port (        
        wb_i_up                     : in wb_mosi_type;
        wb_o_up                     : out wb_miso_type;
        
        addr_map                    : in addr32_array_type(ABN_CNT - 1 downto 0); -- list of base addresses. If you need singe addr in range, put it as a base
        
        wb_i_bottom                 : in wb_miso_array_type(ABN_CNT - 1 downto 0);
        wb_o_bottom                 : out wb_mosi_array_type(ABN_CNT - 1 downto 0)
    );
end wb_arbiter;

architecture behav of wb_arbiter is

begin

ASYNC : process (wb_i_up, wb_i_bottom)
begin
    wb_o_bottom(0) <= WB_MOSI_STUB;
    wb_o_up <= WB_MISO_STUB;
    for i in 0 to ABN_CNT - 1 loop
        if i < ABN_CNT - 1 then
            if wb_i_up.adr_i >= addr_map(i) and wb_i_up.adr_i < addr_map(i+1) then
                -- report integer'image(i) & " Base addr = " & TO_HSTRING(addr_map(i)) & " range end = " & TO_HSTRING(addr_map(i+1));
                wb_o_bottom(i) <= wb_i_up;
                wb_o_up <= wb_i_bottom(i);
            end if;
        else
            if wb_i_up.adr_i >= addr_map(i) then
                -- report integer'image(i) & " Base addr = " & TO_HSTRING(addr_map(i)) & " range end = " & TO_HSTRING(addr_map(i+1));
                wb_o_bottom(i) <= wb_i_up;
                wb_o_up <= wb_i_bottom(i);         
            end if;            
        end if;
    end loop;
end process;

end behav;