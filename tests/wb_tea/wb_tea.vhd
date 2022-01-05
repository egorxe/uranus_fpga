-- This is simplified version of TEA cipher with Wishbone interface to test Ariel FPGA

library ieee;
    use ieee.std_logic_1164.all; 
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

entity wb_tea is
    Port (
        output_data     : out std_logic_vector(31 downto 0);
        wb_clk_i        : in std_logic;
        wb_rst_i        : in std_logic;
        wbs_stb_i       : in std_logic;
        wbs_cyc_i       : in std_logic;
        wbs_we_i        : in std_logic;
        wbs_dat_i       : in std_logic_vector(31 downto 0);
        wbs_adr_i       : in std_logic_vector(31 downto 0);
        wbs_ack_o       : out std_logic;
        wbs_dat_o       : out std_logic_vector(31 downto 0)
    );
end wb_tea;

architecture Behavioral of wb_tea is
    constant NUM_ROUNDS : integer := 32;
    constant DELTA      : std_logic_vector(31 downto 0) := x"9E3779B9";
    signal k0, k1       : std_logic_vector(31 downto 0);
    signal data0        : std_logic_vector(31 downto 0);
    signal round        : integer range 0 to NUM_ROUNDS-1;
    signal sum          : std_logic_vector(31 downto 0);

begin

    
    output_data <= data0;
    
    process(wb_clk_i)
    begin

        if Rising_edge(wb_clk_i) then
            if wb_rst_i = '1' then
                round <= NUM_ROUNDS-1;
                wbs_ack_o <= '0';
            else
                if wbs_cyc_i = '1' and wbs_stb_i = '1' and wbs_ack_o = '1' and wbs_we_i = '1' then
                    case wbs_adr_i(3 downto 2) is
                        when "00" =>
                            k0 <= wbs_dat_i;
                        when "01" =>
                            k1 <= wbs_dat_i;
                        when "10" =>
                            data0 <= wbs_dat_i;
                            sum <= DELTA;
                            round <= 0;
                        when others =>
                            null;
                    end case;
                end if;
                
                if round = NUM_ROUNDS-1 then
                    wbs_ack_o <= '1';
                    null;
                else
                    wbs_ack_o <= '0';
                    sum <= sum + DELTA;
                    round <= round + 1;
                    data0 <= data0 + (((data0(27 downto 0) & "0000") + k0) xor (data0 + sum) xor (data0(31 downto 5) + k1));
                end if;
            end if;
        end if;
    end process;
    
end Behavioral;
