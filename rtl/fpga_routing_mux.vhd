library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;

entity fpga_routing_mux is
    generic (
        INPUTS      : integer := 4;
        CFG_WDT     : integer := 2;
        GND_IN      : integer := -1
    );
    port (
         -- Config signals
        config_i    : in  std_logic_vector(CFG_WDT-1 downto 0);

        -- Logic
        route_i     : in  std_logic_vector(INPUTS-1 downto 0);
        route_o     : out std_logic
    );
end fpga_routing_mux;

architecture arch of fpga_routing_mux is

constant MUX_WDT    : integer := (2**CFG_WDT);

signal route_int    : std_logic_vector(MUX_WDT-1 downto 0);

begin

-- pragma translate_off
assert ((2**CFG_WDT) >= INPUTS) report "Too few conf bits for mux" severity failure;
process
begin
    wait on config_i; -- wait for init
    assert (ToInt(config_i) < INPUTS) or (GND_IN >= 0 and config_i = GND_IN) report "Incorrect mux_state: 0x"
        & ToString(config_i) & " out of " & integer'image(INPUTS) severity failure;
    wait;
end process;
-- pragma translate_on

-- Inject GND
MUX_IN_CONN : for i in 0 to MUX_WDT-1 generate
    -- ensure uniform muxes in case of very stupid synthesis tool
    GND_CONN : if (i >= INPUTS) or (i = GND_IN) generate
        route_int(i) <= '0';
    end generate;
    IN_CONN : if (i < INPUTS) and (i /= GND_IN) generate
        route_int(i) <= route_i(i);
    end generate;
end generate;

-- MUX itself
route_o <= route_int(ToInt(config_i));

end arch;
