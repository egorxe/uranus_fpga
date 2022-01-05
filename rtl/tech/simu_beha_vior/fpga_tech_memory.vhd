library ieee;
    use ieee.std_logic_1164.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;

entity fpga_tech_memory is
    generic (
        MEMORY_WIDTH    : integer;
        MEMORY_DEPTH    : integer
    );
    port (
        clk_i       : in  std_logic;

        ce_a_i      : in  std_logic;
        addr_a_i    : in  std_logic_vector(MEMORY_DEPTH-1 downto 0);
        data_a_o    : out std_logic_vector(MEMORY_WIDTH-1 downto 0);

        we_b_i      : in  std_logic;
        addr_b_i    : in  std_logic_vector(MEMORY_DEPTH-1 downto 0);
        data_b_i    : in  std_logic_vector(MEMORY_WIDTH-1 downto 0)
    );
end fpga_tech_memory;

architecture arch of fpga_tech_memory is

type memory_type is array (0 to (2**MEMORY_DEPTH)-1) of std_logic_vector(MEMORY_WIDTH-1 downto 0);
shared variable memory : memory_type := (others => (others => '0'));

begin

process(clk_i)
begin

    if Rising_edge(clk_i) then
        if (ce_a_i = '1') then
            data_a_o <= memory(ToInt(addr_a_i));
        end if;
        if (we_b_i = '1') then
            memory(ToInt(addr_b_i)) := data_b_i;
        end if;
    end if;

end process;

end arch;
