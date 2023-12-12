library ieee;
    use ieee.std_logic_1164.all;

entity fpga_tech_buffer is
    port (
        I   : in  std_logic;
        Z   : out std_logic
    );
end fpga_tech_buffer;

architecture arch of fpga_tech_buffer is

begin

z <= I;

end arch;

library ieee;
    use ieee.std_logic_1164.all;

entity fpga_tech_clkbuffer is
    port (
        I   : in  std_logic;
        Z   : out std_logic
    );
end fpga_tech_clkbuffer;

architecture arch of fpga_tech_clkbuffer is

begin

z <= I;

end arch;

library ieee;
    use ieee.std_logic_1164.all;

entity fpga_tech_register is
    port (
        clk_i   : in  std_logic;
        rstn_i  : in  std_logic;
        data_i  : in  std_logic;
        data_o  : out std_logic;
        config_i_rst_polarity   : in  std_logic;
        config_i_rst_value      : in  std_logic
    );
end fpga_tech_register;

architecture arch of fpga_tech_register is

begin

process(clk_i, rstn_i)
begin
    if rstn_i = '0' then
        data_o <= '0';
    elsif Rising_edge(clk_i) then
        data_o <= data_i;
    end if;
end process;

end arch;
