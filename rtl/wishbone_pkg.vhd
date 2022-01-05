library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;

package wishbone_pkg is

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  CONSTANTS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

constant WB_DATA_WIDTH               : integer := 32;
constant WB_ADR_WIDTH                : integer := 32;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  TYPES
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
type wb_mosi_type is record
    stb_i                   : std_logic;
    cyc_i                   : std_logic;
    we_i                    : std_logic;
    dat_i                   : std_logic_vector(WB_DATA_WIDTH -1 downto 0);
    adr_i                   : std_logic_vector(WB_ADR_WIDTH - 1 downto 0);
end record;


type wb_miso_type is record
    ack_o                   : std_logic;
    dat_o                   : std_logic_vector(WB_DATA_WIDTH - 1 downto 0);
end record;

type wb_mosi_array_type is array (integer range <>) of wb_mosi_type;
type wb_miso_array_type is array (integer range <>) of wb_miso_type;

type addr32_array_type is array (integer range <>) of std_logic_vector(31 downto 0);

constant WB_MOSI_STUB : wb_mosi_type := ( '0', '0', '0', (others => '0'), (others => '0'));
constant WB_MISO_STUB : wb_miso_type := ('0', (others => '0'));
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  COMPONENTS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

component wb_register is
    generic(
        WB_DATA_WIDTH               : integer := 32;
        WB_ADR_WIDTH                : integer := 32;
        ADDR_CHECK                  : boolean := false; -- do we check register address or only use wbs_cyc_i?
        ENABLE_REG_I                : boolean := false; -- do we use this register to read some from reg_i?
        REG_WIDTH                   : integer := 32 -- =< WB_WIDTH
    );
    port (
        wb_clk_i                    : in std_logic;
        wb_rst_i                    : in std_logic;
        wb_i                        : in wb_mosi_type;
        wb_o                        : out wb_miso_type;  
        reg_o_default_value         : in std_logic_vector(REG_WIDTH - 1 downto 0); -- default value of register   
        wb_reg_addr                 : in std_logic_vector(WB_ADR_WIDTH - 1 downto 0); -- register address        
        reg_o                       : out std_logic_vector(REG_WIDTH - 1 downto 0);
        reg_i                       : in std_logic_vector(REG_WIDTH - 1 downto 0)
    );
end component;

component wb_arbiter is
    generic(
        ABN_CNT                     : integer := 8
        );
    port (        
        wb_i_up                     : in wb_mosi_type;
        wb_o_up                     : out wb_miso_type;
        
        addr_map                    : in addr32_array_type(ABN_CNT - 1 downto 0); -- list of base addresses. If you need singe addr in range, put it as a base
        
        wb_i_bottom                 : in wb_miso_array_type(ABN_CNT - 1 downto 0);
        wb_o_bottom                 : out wb_mosi_array_type(ABN_CNT - 1 downto 0)
    );
end component;

component wb_arbiter_sync is
    generic(
        ABN_CNT                     : integer := 8
        );
    port (        
        wb_clk_i                    : in std_logic;
        wb_rst_i                    : in std_logic;
    
        wb_i_up                     : in wb_mosi_type;
        wb_o_up                     : out wb_miso_type;
        
        addr_map                    : in addr32_array_type(ABN_CNT - 1 downto 0); -- list of base addresses. If you need singe addr in range, put it as a base
        
        wb_i_bottom                 : in wb_miso_array_type(ABN_CNT - 1 downto 0);
        wb_o_bottom                 : out wb_mosi_array_type(ABN_CNT - 1 downto 0)
    );
end component;

component wb_register32 is
    generic(
        REG_O_DEFAULT_VALUE         : in std_logic_vector(31 downto 0) := (others => '0'); -- default value of register     
        ENABLE_REG_I                : in boolean := false
        );
    port (
        wb_clk_i                    : in std_logic;
        wb_rst_i                    : in std_logic;
        
        wb_i                        : in wb_mosi_type;
        wb_o                        : out wb_miso_type;
        
        reg_o                       : out std_logic_vector(31 downto 0);
        reg_i                       : in std_logic_vector(31 downto 0)

    );
end component;

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
--                                  FUNCTIONS
--------------------------------------------------------------------------------
--------------------------------------------------------------------------------


end wishbone_pkg;

package body wishbone_pkg is



end wishbone_pkg;
