--! @title FPGA firmware loader
--! @file fpga_fw_loader.vhd
--! @author anarky
--! @version 0.2a
--! @date 2023-12-01
--!
--! @copyright  Apache License 2.0
--! @details This module reads firmware from OTP and loads it
--! into FPGA via Wishbone interface. This version is configured
--! only for Ophelia FPGA. Later we will make it more flexible.

library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.std_logic_unsigned.all;
    
library fpgalib;
    use fpgalib.fpga_pkg.all;
    use fpgalib.wishbone_pkg.all;
    use fpgalib.fpga_params_pkg.all;
    
entity fpga_fw_loader is
    port (
        wb_rst_i : in std_logic; --! active high reset
        wb_clk_i : in std_logic; --! clock
        
        -- Wishbone secondary
        wb_adr_i : out std_logic_vector(31 downto 0); --! address
        wb_dat_o : in std_logic_vector(31 downto 0); --! read data
        wb_dat_i : out std_logic_vector(31 downto 0); --! write data
        wb_we_i : out std_logic; --! active hihg WE
        wb_sel_i : out std_logic_vector(3 downto 0); --! not connected
        wb_stb_i : out std_logic; --! WB stb signal
        wb_cyc_i : out std_logic; --! WB cyc signal
        wb_ack_o : in std_logic; --! WB ack signal
        self_fw_done : out std_logic;
        self_fw_enable : in std_logic --! Active high enable for loading
    );
end fpga_fw_loader;

architecture rtl of fpga_fw_loader is
constant FW_BYTE_COUNT : integer := 1054;
constant FW_CNT_LIM : integer := 2296; -- bytes in firmware 1054!
constant WB_WDT : integer := 8;
constant BL_WDT : integer := 2;
constant VR_WDT : integer := 7;
constant HR_WDT : integer := 2;
constant FW_FIRST_STAGE : integer := 320;
constant FW_SECOND_STAGE : integer := 800; --187 --867
constant RING_BUF_LEN_POW2 : integer := 5;
constant FPGA_RST_TIME : integer := 25;
type state_type is (idle, fw_fetch, fw_accum, fw_store, fw_load, wb_tap, wb_write, wb_read,
                    stall, release_pads, fabric_reset, fabric_set, wait_fabric_set, 
                    wait_wb_reset, wait_wb_set, wb_set, wb_reset, prog_done);
type v_type is record 
    state : state_type;
    next_state : state_type;
    fw_cnt : integer range 0 to FW_CNT_LIM;
    rdata_buf : std_logic_vector(31 downto 0);
    wdata_buf : std_logic_vector(31 downto 0);
    wb_adr_i : std_logic_vector(31 downto 0);
    wb_dat_i : std_logic_vector(31 downto 0);
    wb_we_i : std_logic;
    wb_sel_i : std_logic_vector(3 downto 0);
    wb_stb_i : std_logic;
    wb_cyc_i : std_logic;
    fw_en : std_logic_vector(2 downto 0);
    rptr : std_logic_vector(RING_BUF_LEN_POW2 - 1 downto 0);
    wptr : std_logic_vector(RING_BUF_LEN_POW2 - 1 downto 0);
    ptr_buf : std_logic_vector(RING_BUF_LEN_POW2 - 1 downto 0);
    fw_ring : std_logic_vector(2**RING_BUF_LEN_POW2 - 1 downto 0);
    tap_ff : std_logic;
    bl_reg : std_logic_vector(BL_WDT - 1 downto 0);
    vr_reg : std_logic_vector(VR_WDT - 1 downto 0);
    hr_reg : std_logic_vector(HR_WDT - 1 downto 0);
    tap_word : std_logic_vector(31 downto 0);
    fetch_cnt : integer range 0 to FW_BYTE_COUNT;
    stall_cnt : integer range 0 to 100;
    stall_time : integer range 0 to 100;
    self_fw_done : std_logic;
end record;
signal r, rin : v_type;

function cnt_diff(WRCNT : std_logic_vector; RDCNT : std_logic_vector) return integer is
    variable result : integer;
begin
    result := 0;
    if WRCNT >= RDCNT then
        result := to_integer(unsigned(WRCNT)) - to_integer(unsigned(RDCNT));
    else
        result := 2**(WRCNT'length) - to_integer(unsigned(RDCNT)) + to_integer(unsigned(WRCNT));
    end if;
    return result;
end;

function to_int(arg : std_logic_vector) return integer is
    variable result : integer;
begin
    return to_integer(unsigned(arg));
end;

begin

wb_adr_i    <= r.wb_adr_i;
wb_dat_i    <= r.wb_dat_i;
wb_we_i     <= r.wb_we_i;
wb_sel_i    <= r.wb_sel_i;
wb_stb_i    <= r.wb_stb_i;
wb_cyc_i    <= r.wb_stb_i;

self_fw_done <= r.self_fw_done;

SYNC : process(wb_clk_i)
begin
	if wb_rst_i = '1' then
		r.state <= idle;
		r.next_state <= idle;
		r.fw_cnt <= 0;
		r.rdata_buf <= (others => '0');
		r.wdata_buf <= (others => '0');
		r.wb_we_i <= '0';
		r.wb_stb_i <= '0';
		r.wb_cyc_i <= '0';
		r.wb_sel_i <= (others => '0');
		r.wb_dat_i <= (others => '0');
		r.wb_adr_i <= (others => '0');
		r.rptr <= (others => '0');
		r.wptr <= (others => '0');
		r.tap_ff <= '0';
		r.fetch_cnt <= 0;
		r.self_fw_done <= '0';
		r.fw_en <= (others => '0');
		r.ptr_buf <= (others => '0');
		r.fw_ring <= (others => '0');
		r.bl_reg <= (others => '0');
		r.vr_reg <= (others => '0');
		r.hr_reg <= (others => '0');
		r.tap_word <= (others => '0');
		r.stall_cnt <= 0;
		r.stall_time <= 0;	
	else
		if rising_edge(wb_clk_i) then
			r <= rin;
		end if;
    end if;
end process;

ASYNC : process(r, wb_ack_o, wb_dat_o, self_fw_enable)
variable v : v_type;
procedure wb_write_req (
                        addr : in std_logic_vector(31 downto 0);
                        data : in std_logic_vector(31 downto 0);
                        next_hop : in state_type
                        ) is
begin
    v.wb_we_i := '1';
    v.wb_stb_i := '1';
    v.wb_adr_i := addr;
    v.wb_dat_i := data;
    v.next_state := next_hop;
    v.state := wb_write;
end procedure;

procedure wb_read_req (
                        addr : in std_logic_vector(31 downto 0);
                        next_hop : in state_type
                        ) is
begin
    v.wb_we_i := '0';
    v.wb_stb_i := '1';
    v.wb_adr_i := addr;
    v.next_state := next_hop;
    v.state := wb_read;
end procedure;

procedure skip_nck (
                        cks : in integer;
                        next_hop : in state_type
                        ) is
begin
    v.state := stall;
    v.next_state := next_hop;
    v.stall_time := cks;
end procedure;

begin
    v := r;
    v.self_fw_done := '0';
    case r.state is
        when idle =>
            if self_fw_enable = '1' then
                wb_write_req(RST_CONFIG_REGISTER_ADDR, X"00000003", fabric_reset);
            end if;
        when fabric_reset =>
            skip_nck(FPGA_RST_TIME, fw_fetch);
        when fw_fetch =>
            if r.fetch_cnt < FW_BYTE_COUNT then
                if cnt_diff(r.wptr, r.rptr) < 2*WB_WDT then
                    wb_read_req(EFUSE_WB_ADDR + r.fetch_cnt, fw_accum);
                    v.fetch_cnt := r.fetch_cnt + 1;
                else
                    v.state := fw_store;
                end if;
            else
                v.state := fw_store;
            end if;
        when fw_accum =>
            for i in 0 to WB_WDT-1 loop
                v.ptr_buf := r.wptr + i;
                v.fw_ring(to_int(v.ptr_buf)) := r.rdata_buf(i);
            end loop;
            v.state := fw_fetch;
            v.wptr := r.wptr + WB_WDT;
        when fw_store =>
            v.state := fw_load;
            if r.fw_cnt < FW_FIRST_STAGE then
                for i in 0 to BL_WDT + VR_WDT + HR_WDT - 1 loop
                    v.ptr_buf := r.rptr + i;
                    if i < BL_WDT then
                        v.bl_reg(i) := v.fw_ring(to_int(v.ptr_buf));
                    elsif i >= BL_WDT and i < VR_WDT + BL_WDT  then
                        v.vr_reg(i-BL_WDT) := v.fw_ring(to_int(v.ptr_buf));
                    else
                        v.hr_reg(i-BL_WDT - VR_WDT) := v.fw_ring(to_int(v.ptr_buf));
                    end if;
                end loop;
                v.fw_en := "111";
                v.tap_word := X"00000007";
                v.rptr := r.rptr + BL_WDT + VR_WDT + HR_WDT;
            elsif r.fw_cnt >= FW_FIRST_STAGE and v.fw_cnt < FW_SECOND_STAGE then
                for i in 0 to BL_WDT + HR_WDT - 1 loop
                    v.ptr_buf := r.rptr + i;
                    if i < BL_WDT then
                        v.bl_reg(i) := v.fw_ring(to_int(v.ptr_buf));
                    else
                        v.hr_reg(i-BL_WDT) := v.fw_ring(to_int(v.ptr_buf));
                    end if;
                end loop; 
                v.fw_en := "101";            
                v.tap_word := X"00000005";
                v.rptr := r.rptr + BL_WDT + HR_WDT;
            elsif r.fw_cnt >= FW_SECOND_STAGE and r.fw_cnt < FW_CNT_LIM then
                for i in 0 to BL_WDT - 1 loop
                    v.ptr_buf := r.rptr + i;
                    v.bl_reg(i) := v.fw_ring(to_int(v.ptr_buf));
                end loop;
                v.fw_en := "001";       
                v.tap_word := X"00000001";             
                v.rptr := r.rptr + BL_WDT;
            else
                v.state := release_pads; -- here we go to fpga init pattern
            end if;
        when fw_load =>      
            if r.fw_en(0) = '1' then
                v.wdata_buf(31 downto BL_WDT) := (others => '0');
                v.wdata_buf(BL_WDT - 1 downto 0) := r.bl_reg;
                wb_write_req(BLOCK_CONFIG_REGISTER_ADDR, v.wdata_buf, fw_load);
                v.fw_en(0) := '0';
            elsif r.fw_en(1) = '1' then
                v.wdata_buf(31 downto VR_WDT) := (others => '0');
                v.wdata_buf(VR_WDT - 1 downto 0) := r.vr_reg;
                wb_write_req(VRNODE_CONFIG_REGISTER_ADDR, v.wdata_buf, fw_load);
                v.fw_en(1) := '0';            
            elsif r.fw_en(2) = '1' then
                v.wdata_buf(31 downto HR_WDT) := (others => '0');
                v.wdata_buf(HR_WDT - 1 downto 0) := r.hr_reg;
                wb_write_req(HRNODE_CONFIG_REGISTER_ADDR, v.wdata_buf, fw_load);
                v.fw_en(2) := '0';               
            else
                v.state := wb_tap;
            end if;
        when wb_tap =>
            if r.tap_ff = '0' then
                wb_write_req(TAP_CONFIG_REGISTER_ADDR, r.tap_word, wb_tap);
                v.tap_ff := '1';
            else
                wb_write_req(TAP_CONFIG_REGISTER_ADDR, X"00000000", fw_fetch);
                v.fw_cnt := r.fw_cnt + 1;
                v.tap_ff := '0';
            end if;
        when wb_write =>
            if wb_ack_o = '1' then
                v.state := r.next_state;
                v.wb_stb_i := '0';
                v.wb_we_i := '0';
            end if;
        when wb_read =>
            if wb_ack_o = '1' then
                v.state := r.next_state;
                v.wb_stb_i := '0';
                v.rdata_buf := wb_dat_o;
            end if;
        when stall =>
            if r.stall_cnt < r.stall_time then
                v.stall_cnt := r.stall_cnt + 1;
            else
                v.stall_cnt := 0;
                v.state := r.next_state;
            end if;
        when release_pads =>
            wb_write_req(RST_CONFIG_REGISTER_ADDR, X"00000001", fabric_set);
        when fabric_set =>
           wb_write_req(RST_CONFIG_REGISTER_ADDR, X"00000000", wait_fabric_set); 
        when wait_fabric_set =>
            skip_nck(FPGA_RST_TIME, wb_reset);
        when wb_reset =>
            wb_write_req(RST_CONFIG_REGISTER_ADDR, X"00000008", wait_wb_reset);
        when wait_wb_reset =>
            skip_nck(FPGA_RST_TIME, wb_set);
        when wb_set =>
            wb_write_req(RST_CONFIG_REGISTER_ADDR, X"00000000", wait_wb_set);
        when wait_wb_set =>
            skip_nck(FPGA_RST_TIME, prog_done);
        when prog_done =>
            v.self_fw_done := '1';
    end case;
    rin <= v;
end process;

end architecture;
