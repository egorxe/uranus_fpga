library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;

entity fpga_register is
    port (
        clk_i       : in  std_logic;
        rst_i       : in  std_logic;
        config_i    : in  register_config_type;
        data_i      : in  std_logic;
        data_o      : out std_logic
    );
end fpga_register;

architecture arch of fpga_register is

begin

--process(clk_i, rst_i)
--begin
    --if (rst_i = config_i.rst_polarity) then
        --data_o <= config_i.rst_value;
    --elsif Rising_edge(clk_i) then
        --data_o <= data_i;
    --end if;
--end process;
process(clk_i, rst_i)
begin
    if (rst_i = '1') then
        data_o <= '0';
    elsif Rising_edge(clk_i) then
        data_o <= data_i;
    end if;
end process;

end arch;
