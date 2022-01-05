library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    use ieee.std_logic_textio.all;
    
use STD.textio.all;

library fpgalib;
    use fpgalib.fpga_pkg.all;

entity fpga_logic_block_tb is
end fpga_logic_block_tb;

architecture arch of fpga_logic_block_tb is

procedure ReadIntFromConfig(l : inout line; i : out integer) is
begin
    assert l'length > 0 report "Malformed configuration file!" severity failure;
    read(l, i);
end;


function LoadConfig(filename : string) return block_config_type is
    file f                  : text;
    variable config_line    : line;
    variable config_int     : integer;
    variable route_config   : std_logic_vector(RNODE_MUX_STATE_WDT-1 downto 0);
    variable config         : block_config_type;
begin
    file_open(f, filename,  read_mode);
    
    while not endfile(f) loop
        readline(f, config_line);
        while config_line(1) = '#' loop
            -- skip comments (without indent and could not be last!)
            readline(f, config_line);
        end loop;
        
        for i in 0 to (CELLS_PER_BLOCK-1) loop
            
            for j in 0 to (LUT_WDT-1) loop
                ReadIntFromConfig(config_line, config_int);
                if (config_int >= 0) then
                    route_config := ToSlVec(config_int, config.route_config(0).mux_state'length);
                else
                    route_config := ROUTE_GND;
                end if;
                config.route_config(i*CELLS_PER_BLOCK+j).mux_state := route_config;
            end loop;
            
            ReadIntFromConfig(config_line, config_int);
            config.cell_config(i).lut_config := ToSlVec(config_int, config.cell_config(i).lut_config'length);
            ReadIntFromConfig(config_line, config_int);
            config.cell_config(i).mux_config := ToSl(config_int);
        end loop;
    end loop;
 
    file_close(f);
    
    return config;
end function;

constant DELAY      : time := 1 us;

signal clk          : std_logic := '0';

signal block_config : block_config_type;
signal inputs       : std_logic_vector(BLOCK_INPUTS-1 downto 0);
signal outputs      : std_logic_vector(BLOCK_OUTPUTS-1 downto 0);

begin

logic_block : entity work.fpga_logic_block
    port map (
        clk_i       => clk,
        config_i    => block_config,

        inputs_i    => inputs,
        outputs_o   => outputs
    );


-- Generate stimulus
process
begin
    block_config <= LoadConfig("fpga.cfg");
    inputs <= (others => '0');
    
    for i in 0 to (2**BLOCK_INPUTS)-1 loop
        wait for DELAY;
        inputs <= inputs + 1;
    end loop;
    
    report "All possible stimulus values generated";

end process;

end arch;