library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.fpga_params_pkg.all;

entity fpga_lut is
    generic (
        LUT_WIDTH : integer := FPGA_LUT_WIDTH
    );
    port (
        glb_rstn_i  : in  std_logic;
        config_i    : in  std_logic_vector((2**LUT_WIDTH)-1 downto 0);

        logic_i     : in  std_logic_vector(LUT_WIDTH-1 downto 0);
        logic_o     : out std_logic
    );
end fpga_lut;

architecture arch of fpga_lut is

constant LUT_SIZE   : integer := 2**LUT_WIDTH;
--type lut_mem_type is array(FPGA_LUT_SIZE-1 downto 0) of std_logic;
--signal lut_mem 	: lut_mem_type;

signal lut_out	        : std_logic;
signal sublut0_out      : std_logic;
signal sublut1_out      : std_logic;

signal buffered_out0    : std_logic;
signal buffered_out1    : std_logic;

begin

-- pragma translate_off
-- Check consistency
assert (LUT_WIDTH > 0);
process
begin
    wait until (glb_rstn_i = '1'); -- wait for init
    assert (config_i <= (2**LUT_SIZE)-1) report "Incorrect LUT state: 0x" & ToString(config_i) severity failure;
    wait;
end process;
-- pragma translate_on

--lut_mem <= lut_mem_type(config_i);
--lut_out <= lut_mem(ToInt(X_to_zero(logic_i)));

LUT1 : if LUT_WIDTH = 1 generate
    sublut0_out <= config_i(0);
    sublut1_out <= config_i(1);
end generate;

SUBLUTS : if LUT_WIDTH > 1 generate
    sublut0 : entity fpgalib.fpga_lut
        generic map (
            LUT_WIDTH   => LUT_WIDTH-1
        )
        port map (
            glb_rstn_i   => glb_rstn_i,
            config_i    => config_i((LUT_SIZE/2)-1 downto 0),
            
            logic_i     => logic_i(LUT_WIDTH-2 downto 0),
            logic_o     => sublut0_out
        );
        
    sublut1 : entity fpgalib.fpga_lut
        generic map (
            LUT_WIDTH   => LUT_WIDTH-1
        )
        port map (
            glb_rstn_i   => glb_rstn_i,
            config_i    => config_i(LUT_SIZE-1 downto LUT_SIZE/2),
            
            logic_i     => logic_i(LUT_WIDTH-2 downto 0),
            logic_o     => sublut1_out
        );
end generate;

-- LUT logic which ensures no X propagation in all valid cases
process(logic_i, sublut0_out, sublut1_out)
begin
    if (sublut0_out = '0') and (sublut1_out = '0') then
        lut_out <= '0';
    elsif (sublut0_out = '1') and (sublut1_out = '1') then
        lut_out <= '1';
    elsif (logic_i(LUT_WIDTH-1) = '0') then
        lut_out <= sublut0_out;
    elsif (logic_i(LUT_WIDTH-1) = '1') then
        lut_out <= sublut1_out;
    else
        lut_out <= '0'; -- !!! (should not happen!)
        --lut_out <= '-'; -- dont care for synthesis (should not happen!)
        -- pragma translate_off
        lut_out <= 'X'; -- X in simulation
        -- pragma translate_on
    end if;
end process;

BREAKER : if LUT_WIDTH = FPGA_LUT_WIDTH generate
    -- this three buffer structure is needed to break loops & constraint paths at the same time in OpenROAD
    lut_tfinish  : fpga_tech_buffer port map (lut_out, buffered_out0);
    loop_breaker : fpga_tech_buffer port map (buffered_out0, buffered_out1);
    lut_tstart   : fpga_tech_buffer port map (buffered_out1, logic_o);
else generate
    logic_o <= lut_out;
end generate;

end arch;
