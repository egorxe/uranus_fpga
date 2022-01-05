-- Simple Wishbone slave register

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio;

use std.textio.all;

library fpgalib;
    use fpgalib.wishbone_pkg.all;
    
entity wb_register32 is
    generic(
        REG_O_DEFAULT_VALUE         : in std_logic_vector(31 downto 0) := (others => '0'); -- default value of register     
        ENABLE_REG_I                : in boolean := false
        );
    port (
        wb_clk_i                    : in std_logic;
        wb_rst_i                    : in std_logic;
        
        wb_i                        : in wb_mosi_type;
        wb_o                        : out wb_miso_type;
        
        reg_o                       : out std_logic_vector(31 downto 0);
        reg_i                       : in std_logic_vector(31 downto 0)

    );
end wb_register32;


architecture behav of wb_register32 is
signal reg_o_buf : std_logic_vector(31 downto 0);

begin

reg_o <= reg_o_buf;

SYNC : process (wb_clk_i, wb_rst_i) is
begin
    if wb_rst_i = '1' then
        reg_o_buf <= REG_O_DEFAULT_VALUE;
        wb_o.ack_o <= '0';
        wb_o.dat_o <= (others=>'0');
    else   
        if rising_edge(wb_clk_i) then
            wb_o.ack_o <= '1';
            if ENABLE_REG_I = true then
                wb_o.dat_o <= reg_i;
            else
                wb_o.dat_o <= reg_o_buf;
            end if;            
            if wb_i.cyc_i = '1' and wb_i.stb_i = '1' then
                if wb_i.we_i = '1' then
                    reg_o_buf <= wb_i.dat_i;
                end if;
            end if;
        end if;
    end if;
end process;

end behav;
