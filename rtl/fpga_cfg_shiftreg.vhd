library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

--~ library fpgalib;
    --~ use fpgalib.fpga_pkg.all;
    --~ use fpgalib.fpga_params_pkg.all;

entity fpga_cfg_shiftreg is
    generic (
        CONFIG_WDT  : integer := 256
    );
    port (
        -- Clock & enable
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;

        -- Shift input & output
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Loaded config data
        config_o        : out std_logic_vector(CONFIG_WDT-1 downto 0)
    );
end fpga_cfg_shiftreg;

architecture arch of fpga_cfg_shiftreg is

constant dummy_config_register  : std_logic_vector(CONFIG_WDT-1 downto 0) := (others=>'0');

signal config_data : std_logic_vector(CONFIG_WDT-1 downto 0);

begin

config_shift_o <= config_data(0);

config_o <= config_data
-- pragma translate_off
-- simulation hack to workaround combinational loops while programming (should not be a problem with SDF)
when config_ena_i = '0' else dummy_config_register
-- pragma translate_on
;

-- Shift register loading config
process(config_clk_i)
begin
    if Rising_edge(config_clk_i) then
        config_data(CONFIG_WDT-1) <= config_shift_i;
        config_data(CONFIG_WDT-2 downto 0) <= config_data(CONFIG_WDT-1 downto 1);
    end if;
end process;

end arch;
