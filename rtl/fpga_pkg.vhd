library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

library fpgalib;
    use fpgalib.fpga_params_pkg.all;

package fpga_pkg is

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  CONSTANTS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

constant FABRIC_X           : integer := work.fpga_params_pkg.FPGA_FABRIC_SIZE_X;
constant FABRIC_Y           : integer := work.fpga_params_pkg.FPGA_FABRIC_SIZE_Y;

constant FABRIC_BLOCKS      : integer := (FABRIC_X*FABRIC_Y) - FABRIC_IO - 4;

constant BLOCK_CONFIG_REGISTER_ADDR     : std_logic_vector(31 downto 0):= X"30100000";
constant VRNODE_CONFIG_REGISTER_ADDR    : std_logic_vector(31 downto 0) := X"30200000";
constant HRNODE_CONFIG_REGISTER_ADDR    : std_logic_vector(31 downto 0):= X"30300000";
constant RST_CONFIG_REGISTER_ADDR       : std_logic_vector(31 downto 0):= X"30A00000";
constant TAP_CONFIG_REGISTER_ADDR       : std_logic_vector(31 downto 0):= X"30E00000";
constant FPGA_FABRIC_WB_ADDR            : std_logic_vector(31 downto 0):= X"30F00000";
    
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  TYPES
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

type direction_type is (DIR_UP, DIR_DOWN, DIR_LEFT, DIR_RIGHT);

subtype cells_logic_in_type  is std_logic_vector(FPGA_LUT_WIDTH -1 downto 0);

type rnode_tracks_array is array (0 to TRACKS_PER_RNODE-1) of std_logic_vector(RNODE_INPUTS-1 downto 0);


------------------------ Config types ------------------------

subtype lut_config_type  is std_logic_vector(FPGA_LUT_SIZE-1 downto 0);
constant LUT_CONFIG_TYPE_SIZE : integer := lut_config_type'length;

type sr_to_fpga_config_type is record
	clk : std_logic;
	sda : std_logic;
end record;

type sr_from_fpga_config_type is record
	sda : std_logic;
end record;

type sr_to_fpga_config_array_type is array (integer range <>) of sr_to_fpga_config_type;
type sr_from_fpga_config_array_type is array (integer range <>) of sr_from_fpga_config_type;

type register_config_type is record
    rst_polarity    : std_logic;
    rst_value       : std_logic;
end record;
constant REGISTER_CONFIG_TYPE_SIZE : integer := 2;

type cell_config_type is record
    lut_config      : lut_config_type;
    --reg_config      : register_config_type;
    mux_config      : std_logic;
end record;
constant cell_config_zero : cell_config_type := ((others => '0'), '0');
constant CELL_CONFIG_TYPE_SIZE : integer := LUT_CONFIG_TYPE_SIZE + 1;

subtype route_mux_state_type is std_logic_vector(RNODE_MUX_STATE_WDT-1 downto 0);
constant ROUTE_MUX_STATE_TYPE_SIZE : integer := route_mux_state_type'length;

subtype lbcross_mux_state_type is std_logic_vector(LBCROSS_MUX_STATE_WDT-1 downto 0);
constant lbcross_mux_state_zero : lbcross_mux_state_type := (others => '0');
constant LBCROSS_MUX_STATE_TYPE_SIZE : integer := lbcross_mux_state_type'length;

subtype binput_mux_state_type is std_logic_vector(BINPUT_MUX_STATE_WDT-1 downto 0);
constant BINPUT_MUX_STATE_TYPE_SIZE : integer := binput_mux_state_type'length;

type lbcross_mux_config_array is array (0 to BLOCK_CROSS_MUXES-1) of lbcross_mux_state_type;
constant lbcross_mux_config_array_zero : lbcross_mux_config_array := (others => lbcross_mux_state_zero);
constant LBCROSS_MUX_CONFIG_ARRAY_SIZE : integer := lbcross_mux_config_array'length * LBCROSS_MUX_STATE_TYPE_SIZE;

type cell_config_array is array (0 to CELLS_PER_BLOCK-1) of cell_config_type;
constant CELL_CONFIG_ARRAY_SIZE : integer := cell_config_array'length * CELL_CONFIG_TYPE_SIZE;

type block_config_type is record
    crossbar_config :   lbcross_mux_config_array;
    cell_config     :   cell_config_array;
end record;
constant block_config_zero : block_config_type := (lbcross_mux_config_array_zero, (others => cell_config_zero));
constant BLOCK_CONFIG_TYPE_SIZE : integer := LBCROSS_MUX_CONFIG_ARRAY_SIZE + CELL_CONFIG_ARRAY_SIZE;

type route_mux_node_config_array is array (0 to TRACKS_PER_RNODE-1) of route_mux_state_type;
constant ROUTE_MUX_NODE_CONFIG_ARRAY_SIZE : integer := route_mux_node_config_array'length * ROUTE_MUX_STATE_TYPE_SIZE;

type route_mux_binput_config_array is array (0 to BLOCK_INPUTS-1) of binput_mux_state_type;
constant ROUTE_MUX_BINPUT_CONFIG_ARRAY_SIZE : integer := route_mux_binput_config_array'length * BINPUT_MUX_STATE_TYPE_SIZE;
type route_mux_binput_xy_config_array is array (1 to FABRIC_BLOCKS_X, 1 to FABRIC_BLOCKS_Y) of route_mux_binput_config_array; -- 1-based to reflect real geometry
constant ROUTE_MUX_BINPUT_XY_CONFIG_ARRAY_SIZE : integer := route_mux_binput_xy_config_array'length(1) * route_mux_binput_xy_config_array'length(2) * ROUTE_MUX_BINPUT_CONFIG_ARRAY_SIZE;

type route_node_config_type is record
    track_config    : route_mux_node_config_array;
end record;
constant ROUTE_NODE_CONFIG_TYPE_SIZE : integer := ROUTE_MUX_NODE_CONFIG_ARRAY_SIZE;

type io_config_array is array (0 to FABRIC_IO-1) of binput_mux_state_type;
constant IO_CONFIG_ARRAY_SIZE : integer := io_config_array'length * BINPUT_MUX_STATE_TYPE_SIZE;

type block_xy_config_array is array (1 to FABRIC_BLOCKS_X, 1 to FABRIC_BLOCKS_Y) of block_config_type;
constant BLOCK_XY_CONFIG_ARRAY_SIZE : integer := block_xy_config_array'length(1) * block_xy_config_array'length(2) * BLOCK_CONFIG_TYPE_SIZE;
type rnode_vxy_config_array is array (0 to FABRIC_VROUTE_X-1, 1 to FABRIC_VROUTE_Y) of route_node_config_type;
constant RNODE_VXY_CONFIG_ARRAY_SIZE : integer := rnode_vxy_config_array'length(1) * rnode_vxy_config_array'length(2) * ROUTE_NODE_CONFIG_TYPE_SIZE;
type rnode_hxy_config_array is array (1 to FABRIC_HROUTE_X, 0 to FABRIC_HROUTE_Y-1) of route_node_config_type;
constant RNODE_HXY_CONFIG_ARRAY_SIZE : integer := rnode_hxy_config_array'length(1) * rnode_hxy_config_array'length(2) * ROUTE_NODE_CONFIG_TYPE_SIZE;

type fabric_config_type is record
    block_in_config     : route_mux_binput_xy_config_array;
    block_config        : block_xy_config_array;
    io_config           : io_config_array;
    up_rnode_config     : rnode_vxy_config_array;
    down_rnode_config   : rnode_vxy_config_array;
    left_rnode_config   : rnode_hxy_config_array;
    right_rnode_config  : rnode_hxy_config_array;
end record;

-- Config constants
constant BLOCK_IN_CFG_START         : integer := 0;
constant BLOCK_CFG_START            : integer := BLOCK_IN_CFG_START + ROUTE_MUX_BINPUT_XY_CONFIG_ARRAY_SIZE;
constant IO_CFG_START               : integer := BLOCK_CFG_START + BLOCK_XY_CONFIG_ARRAY_SIZE;
constant UP_RNODE_CFG_START         : integer := IO_CFG_START + IO_CONFIG_ARRAY_SIZE;
constant DOWN_RNODE_CFG_START       : integer := UP_RNODE_CFG_START + RNODE_VXY_CONFIG_ARRAY_SIZE;
constant LEFT_RNODE_CFG_START       : integer := DOWN_RNODE_CFG_START + RNODE_VXY_CONFIG_ARRAY_SIZE;
constant RIGHT_RNODE_CFG_START      : integer := LEFT_RNODE_CFG_START + RNODE_HXY_CONFIG_ARRAY_SIZE;

constant FABRIC_CONFIG_SIZE         : integer := RIGHT_RNODE_CFG_START + RNODE_HXY_CONFIG_ARRAY_SIZE;
constant CFG_LOADER_DATA_WDT        : integer := 32;

constant ZERO_CFG_WHILE_LOAD        : boolean := false;


--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  COMPONENTS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Tech components for verilog instances
component fpga_tech_register is
    port (
        clk_i                   : in  std_logic;
        rstn_i                  : in  std_logic;
        config_i_rst_polarity   : in  std_logic;
        config_i_rst_value      : in  std_logic;
        data_i                  : in  std_logic;
        data_o                  : out std_logic
    );
end component;

component fpga_tech_buffer is
    port (
        i           : in  std_logic;
        z           : out std_logic
    );
end component;

component fpga_tech_clkbuffer is
    port (
        i           : in  std_logic;
        z           : out std_logic
    );
end component;

-- Blackbox component instances
component fpga_routing_node_wcfg is
    port (
        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        route_i     : rnode_tracks_array;
        route_o     : out std_logic_vector(TRACKS_PER_RNODE-1 downto 0)
    );
end component;

component fpga_struct_block is
    --generic (
        --POS_X           : integer;
        --POS_Y           : integer;
        --BLOCK_INPUTS    : integer := BLOCK_INPUTS;
        --BLOCK_OUTPUTS   : integer := BLOCK_OUTPUTS
    --);
    port (
        clk_i       : in  std_logic;
        glb_rstn_i  : in  std_logic;

        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Connections to routing fabric
        inputs_up_i     : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_right_i  : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_down_i   : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        inputs_left_i   : in  std_logic_vector(TOTAL_TRACKS-1 downto 0);
        outputs_o       : out std_logic_vector(BLOCK_OUTPUTS-1 downto 0)
    );
end component;

component fpga_logic_block is
    port (
        clk_i       : in  std_logic;
        glb_rstn_i   : in  std_logic;

        -- Config signals
        config_clk_i    : in  std_logic;
        config_ena_i    : in  std_logic;
        config_shift_i  : in  std_logic;
        config_shift_o  : out std_logic;

        -- Logic IO
        inputs_i        : in  std_logic_vector(BLOCK_INPUTS-1 downto 0);
        outputs_o       : out std_logic_vector(BLOCK_OUTPUTS-1 downto 0)
    );
end component;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  FUNCTIONS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- Position stuff
function IsCorner(x : integer; y : integer) return boolean;
function IsIoBlock(x : integer; y : integer) return boolean;
function IsLogicBlock(x : integer; y : integer) return boolean;
function IsMemoryBlock(x : integer; y : integer) return boolean;
function IsMemoryBlockStart(x : integer; y : integer) return boolean;
function IsStructBlock(x : integer; y : integer) return boolean;
--function XYtoIO(x : integer; y : integer) return integer;
function XYtoIOl(x : integer; y : integer) return integer;
function XYtoIOr(x : integer; y : integer) return integer;
function BlkInputReduction(vec : std_logic_vector(TRACKS_PER_RNODE*2-1 downto 0); index : integer) return std_logic_vector;

-- General helpers

function DivUp(a : integer; b : integer) return integer;

function RoundUp(a : integer; b : integer) return integer;

function or_all(a : std_logic_vector) return std_logic;

function and_all(a : std_logic_vector) return std_logic;

function Char2QuadBits(c : character) return std_logic_vector;

function ToSL(a : integer) return std_logic;
function ToSLVec(a : integer; size : integer) return std_logic_vector;
function ToSLVec(a : unsigned; size : integer) return std_logic_vector;
function ToSLVec(s : string; size : integer) return std_logic_vector;

function OnesVec(size : integer) return std_logic_vector;
function ZeroVec(size : integer) return std_logic_vector;
function ZeroVec(vec : std_logic_vector) return std_logic_vector;

function LsbOne(a : std_logic_vector) return integer;

function ToInt(a : std_logic_vector) return integer;

function ExtVec(a : std_logic_vector; size : integer) return std_logic_vector;
function ExtVec(a : std_logic; size : integer) return std_logic_vector;

function ToString(a : std_logic_vector) return string;
function ToString(a : integer) return string;

function X_to_zero(a : std_logic_vector) return std_logic_vector;

-- Synthesis types
function TargetIsSimulation return boolean;
function TargetIsASIC return boolean;
function TargetIsTSMC28HPCP return boolean;
function TargetIsUnknown return boolean;

end fpga_pkg;

package body fpga_pkg is

-- Positional stuff functions

function IsCorner(x : integer; y : integer) return boolean is
begin
    if ((x = 0) and (y = 0)) or
        ((x = 0) and (y = FABRIC_Y-1)) or
        ((x = FABRIC_X-1) and (y = 0)) or
        ((x = FABRIC_X-1) and (y = FABRIC_Y-1))
    then
        return True;
    else
        return False;
    end if;
end;

function IsIoBlock(x : integer; y : integer) return boolean is
begin
    return ((x = 0) or (y = 0) or (x = FABRIC_X-1) or (y = FABRIC_Y-1)) and not IsCorner(x, y);
end;

function IsStructBlock(x : integer; y : integer) return boolean is
begin
    return (not IsIoBlock(x, y)) and (not IsCorner(x, y));
end;

function IsMemoryBlockStart(x : integer; y : integer) return boolean is
begin
    return IsStructBlock(x, y) and (x >= MEMORY_STARTX)
        and (((x - MEMORY_STARTX) mod MEMORY_REPEATX) = 0)
        and ((y mod MEMORY_SIZE_Y) = 0);
end;

function IsMemoryBlock(x : integer; y : integer) return boolean is
begin
    return IsStructBlock(x, y) and (x >= MEMORY_STARTX)
        and (((x - MEMORY_STARTX) mod MEMORY_REPEATX) < MEMORY_SIZE_X);
end;

function IsLogicBlock(x : integer; y : integer) return boolean is
begin
    return IsStructBlock(x, y) and (not IsMemoryBlock(x, y));
end;

function XYtoIOr(x : integer; y : integer) return integer is
    variable i : integer := -1;
begin
    assert ((x = 0) or (y = 0) or (x = FABRIC_X-1) or (y = FABRIC_Y-1)) and (not IsCorner(x, y))
    report "Incorect IO coords " & ToString(x) & "," & ToString(y) severity failure;

    if (x = 0) then
        -- left edge
        i := (y - 1) * PINS_PER_PAD;
    elsif (y = FABRIC_Y-1) then
        -- top edge
        i := LEFT_IO + (x - 1) * PINS_PER_PAD;
    elsif (x = FABRIC_X-1) then
        -- right edge
        i := LEFT_IO + UP_IO + (y - 1) * PINS_PER_PAD;
    elsif (y = 0) then
        -- bottom edge
        i := LEFT_IO + UP_IO + RIGHT_IO + (x - 1) * PINS_PER_PAD;
    end if;

    --i := i * PINS_PER_PAD;
    assert (i >= 0) and (i < FABRIC_IO) report "Wrong IO pin: " & ToString(i) severity failure;

    return i;
end;

function XYtoIOl(x : integer; y : integer) return integer is
    variable j : integer := -1;
begin
    j := XYtoIOr(x,y) + PINS_PER_PAD - 1;
    assert (j >= 0) and (j < FABRIC_IO) report "Wrong IO pin: " & ToString(j) severity failure;
    return j;
end;

-- Take each Nth input only, helps reduce number of muxes (N=BLOCK_IN_MUXES_COEF)
function BlkInputReduction(vec : std_logic_vector(TRACKS_PER_RNODE*2-1 downto 0); index : integer) return std_logic_vector is
    variable res    : std_logic_vector(BLOCK_INPUTS_MUXES-1 downto 0);
    constant STEP   : integer := index / (BLOCK_IN_PERSIDE / BLOCK_IN_MUXES_COEF); -- ?probably not correct for all cases?
begin
    for i in 0 to BLOCK_INPUTS_MUXES/2-1 loop
        res(i) := vec((i * BLOCK_IN_MUXES_COEF) + STEP);
        res(i+BLOCK_INPUTS_MUXES/2) := vec((i * BLOCK_IN_MUXES_COEF) + TRACKS_PER_RNODE + STEP);
    end loop;

    return res;
end;

-- OR all elements of std_logic_vector
function or_all(a : std_logic_vector) return std_logic is
    variable result : std_logic;
begin
    result := '0';

    for i in a'high downto a'low  loop
        result := result or a(i);
    end loop;

    return result;
end;


-- AND all elements of std_logic_vector
function and_all(a : std_logic_vector) return std_logic is
    variable result : std_logic;
begin
    result := '1';

    for i in a'high downto a'low loop
        result := result and a(i);
    end loop;

    return result;
end;


-- Std_logic_vector to integer shortcut
function ToInt(a : std_logic_vector) return integer is
begin
    return to_integer(unsigned(a));
end;


function Char2QuadBits(c : character) return std_logic_vector is
    variable result : std_logic_vector(3 downto 0);
begin
    case c is
        when '0'       => result := x"0";
        when '1'       => result := x"1";
        when '2'       => result := x"2";
        when '3'       => result := x"3";
        when '4'       => result := x"4";
        when '5'       => result := x"5";
        when '6'       => result := x"6";
        when '7'       => result := x"7";
        when '8'       => result := x"8";
        when '9'       => result := x"9";
        when 'A' | 'a' => result := x"A";
        when 'B' | 'b' => result := x"B";
        when 'C' | 'c' => result := x"C";
        when 'D' | 'd' => result := x"D";
        when 'E' | 'e' => result := x"E";
        when 'F' | 'f' => result := x"F";
        when others =>
            report
            "Char2QuadBits got '" & c & "', expected a hex character."
            severity error;
    end case;

    return result;
end;


-- String to std_logic_vector
function ToSLVec(s : string; size : integer) return std_logic_vector is
    variable res : std_logic_vector((s'length)*4-1 downto 0);
begin
    for i in 0 to s'length-1 loop
        res(((i+1)*4)-1 downto i*4) := Char2QuadBits(s(s'length-i));
    end loop;

    return ExtVec(res, size);
end;


-- Integer to std_logic_vector shortcut
function ToSLVec(a : integer; size : integer) return std_logic_vector is
begin
    return std_logic_vector(to_unsigned(a, size));
end;


-- Integer to std_logic_vector shortcut
function ToSLVec(a : unsigned; size : integer) return std_logic_vector is
begin
    return std_logic_vector(a);
end;

function ToSL(a : integer) return std_logic is
begin
    assert (a = 0) or (a = 1) report "Not {0,1} in ToSL function!" severity warning;
    if (a = 0) then
        return '0';
    else
        return '1';
    end if;
end;


-- All ones std_logic_vector shortcut
function OnesVec(size : integer) return std_logic_vector is
    constant ret : std_logic_vector(size-1 downto 0) := (others => '1');
begin
    return ret;
end;


-- Zero std_logic_vector shortcut
function ZeroVec(size : integer) return std_logic_vector is
begin
    return ToSLVec(0, size);
end;


-- Zero std_logic_vector shortcut
function ZeroVec(vec : std_logic_vector) return std_logic_vector is
begin
    return ToSLVec(0, vec'length);
end;


-- Extend std_logic_vector to desired width
function ExtVec(a : std_logic_vector; size : integer) return std_logic_vector is
begin
    if (a'length >= size) then
        return a(size-1+a'right downto a'right);
    else
        return ZeroVec(size-a'length) & a;
    end if;
end;

-- Extend std_logic to desired width
function ExtVec(a : std_logic; size : integer) return std_logic_vector is
    variable v : std_logic_vector(0 downto 0);
begin
    v(0) := a;
    return ExtVec(v, size);
end;


-- Get number of least significant bit which is '1'
function LsbOne(a : std_logic_vector) return integer is
begin
    for i in a'low to a'high loop
        if (a(i) = '1') then
            return i;
        end if;
    end loop;

    -- if not fount return -1
    return -1;
end;


-- Integer division with rounding up
function DivUp(a : integer; b : integer) return integer is
    variable result : integer;
begin
    if (a rem b) = 0 then
        result := a / b;
    else
        result := (a / b) + 1;
    end if;

    return result;
end;


-- Integer rounding up
function RoundUp(a : integer; b : integer) return integer is
begin
    return DivUp(a, b) * b;
end;


-- Vector to string shortcut
function ToString(a : std_logic_vector) return string is
begin
    -- pragma translate_off
    return TO_HSTRING(a);
    -- pragma translate_on
    return "";
end;


-- Integer to string shortcut
function ToString(a : integer) return string is
begin
    return integer'image(a);
end;

-- Not X test (safe for synth)
function notx(d : std_logic_vector) return boolean is
    variable res : boolean;
begin
    res := true;
-- pragma translate_off
    res := not is_x(d);
-- pragma translate_on
    return (res);
end;
function notx(d : std_logic) return boolean is
    variable res : boolean;
begin
    res := true;
-- pragma translate_off
    res := not is_x(d);
-- pragma translate_on
    return (res);
end;

-- Zero metastate (X, U, etc) bits, but keep others
function X_to_zero(a : std_logic_vector) return std_logic_vector is
    variable res : std_logic_vector(a'length-1 downto 0);
begin
    res := (others => '0');
    for i in 0 to a'length-1 loop
        if (notx(a(i))) then
            res(i) := a(i);
        end if;
    end loop;
    return res;
end;


-- Synthesis targets
function TargetIsSimulation return boolean is
begin
    if work.fpga_params_pkg.TARGET_TECHNOLOGY(1 to 4) = "SIMU" then
        return True;
    else
        return False;
    end if;
end;

function TargetIsASIC return boolean is
begin
    if work.fpga_params_pkg.TARGET_TECHNOLOGY(1 to 4) = "ASIC" then
        return True;
    else
        return False;
    end if;
end;

function TargetIsTSMC28HPCP return boolean is
begin
    if work.fpga_params_pkg.TARGET_TECHNOLOGY = "ASIC_TSMC_28HP" then
        return True;
    else
        return False;
    end if;
end;

function TargetIsUnknown return boolean is
begin
    if TargetIsTSMC28HPCP then
        return False;
    elsif TargetIsSimulation then
        return False;
    else
        return True;
    end if;
end;

end fpga_pkg;
