library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio;

use std.textio.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;
    use fpgalib.fpga_tb_pkg.all;

entity fpga_config_sender is
    generic (
        CONFIG_FILENAME     : string
    );
    port (
        config_clk_o        : out  std_logic;

        config_block_ena_o  : out std_logic_vector(CONFIG_CHAINS_BLOCK-1 downto 0);
        config_block_dat_o  : out std_logic_vector(CONFIG_CHAINS_BLOCK-1 downto 0);

        config_vrnode_ena_o : out std_logic_vector(CONFIG_CHAINS_VRNODE-1 downto 0);
        config_vrnode_dat_o : out std_logic_vector(CONFIG_CHAINS_VRNODE-1 downto 0);

        config_hrnode_ena_o : out std_logic_vector(CONFIG_CHAINS_HRNODE-1 downto 0);
        config_hrnode_dat_o : out std_logic_vector(CONFIG_CHAINS_HRNODE-1 downto 0);

        rst_o               : out std_logic
    );
end fpga_config_sender;

architecture arch of fpga_config_sender is

type config_state_type is (PRECONFIG, CONFIG_LOAD, CONFIG_DONE);
type bit_file  is file of character;

signal config_block_ena : std_logic_vector(CONFIG_CHAINS_BLOCK-1 downto 0) := (others => '0');
signal chain_bit        : integer := 0;

signal config_clk_buf	: std_logic := '0';

impure function ReadBit(file f : bit_file) return std_logic is
    variable buf : character := ' ';
begin
    while (buf /= '1') and (buf /= '0') loop
        assert (not endfile(f)) report "Bitstream file ended unexpetedly!" severity failure;
        read(f, buf);
    end loop;
    case buf is
        when '1' =>
            return '1';
        when '0' =>
            return '0';
        when others =>
            report "Bitstream file has unexpected chars!" severity failure;
    end case;

    return 'X'; -- just for fun :)
end;

begin


config_clk_buf <= not config_clk_buf after CFG_CLK_PERIOD/2;

config_clk_o <= config_clk_buf;

config_block_ena_o <= config_block_ena;

-- Push data via config iface
process(config_clk_buf)
    variable cnt    : integer := 0;
    variable state  : config_state_type := PRECONFIG;
    file bitstream_file : bit_file open read_mode is CONFIG_FILENAME;
begin
    if Falling_edge(config_clk_buf) then
        case state is
            when PRECONFIG =>
                -- Wait first 100 clocks
                rst_o <= '1';
                config_block_ena <= (others => '0');
                config_vrnode_ena_o <= (others => '0');
                config_hrnode_ena_o <= (others => '0');
                if cnt < 100 then
                    cnt := cnt + 1;
                else
                    report "Loaging FPGA bitstream from file " & CONFIG_FILENAME;
                    cnt := 0;
                    state := CONFIG_LOAD;
                end if;

            when CONFIG_LOAD =>
                -- Logic block config
                if (cnt < BLOCK_CFGCHAIN_LEN) then
                    config_block_ena <= (others => '1');
                    for i in 0 to CONFIG_CHAINS_BLOCK-1 loop
                        config_block_dat_o(i) <= ReadBit(bitstream_file);
                    end loop;
                    --report integer'image(cnt) & " " & integer'image(BLOCK_CFGCHAIN_LEN);
                else
                    config_block_ena <= (others => '0');
                end if;

                -- Vertical routing node config
                if (cnt < VRNODE_CFGCHAIN_LEN) then
                    config_vrnode_ena_o <= (others => '1');
                    for i in 0 to CONFIG_CHAINS_VRNODE-1 loop
                        config_vrnode_dat_o(i) <= ReadBit(bitstream_file);
                    end loop;
                else
                    config_vrnode_ena_o <= (others => '0');
                end if;

                -- Horizontal routing node config
                if (cnt < HRNODE_CFGCHAIN_LEN) then
                    config_hrnode_ena_o <= (others => '1');
                    for i in 0 to CONFIG_CHAINS_HRNODE-1 loop
                        config_hrnode_dat_o(i) <= ReadBit(bitstream_file);
                    end loop;
                else
                    config_hrnode_ena_o <= (others => '0');
                end if;

                if (cnt >= BLOCK_CFGCHAIN_LEN) and (cnt >= HRNODE_CFGCHAIN_LEN)  and (cnt >= VRNODE_CFGCHAIN_LEN) then
                    cnt := 0;
                    state := CONFIG_DONE;
                    report "Loaging FPGA bitstream completed";
                else
                    cnt := cnt + 1;
                end if;

            when CONFIG_DONE =>
                -- Wait 100 more clocks before reset release
                if cnt < 100 then
                    cnt := cnt + 1;
                else
                    rst_o <= '0';
                end if;

        end case;
    end if;
end process;

end arch;
