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
