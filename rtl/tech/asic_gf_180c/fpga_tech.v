module gf180mcu_fd_sc_mcu7t5v0__dffrnq_1( CLK, D, RN, Q );
input CLK, D, RN;
output Q;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__buf_1( I, Z );
input I;
output Z;
endmodule

module gf180mcu_fd_sc_mcu7t5v0__clkbuf_1( I, Z );
input I;
output Z;
endmodule

module fpga_tech_register
  (input  clk_i,
   input  rstn_i,
   input  config_i_rst_polarity,
   input  config_i_rst_value,
   input  data_i,
   output data_o);

  gf180mcu_fd_sc_mcu7t5v0__dffrnq_1 register (
    .CLK(clk_i),
    .D( data_i ),
    .Q( data_o ),
    .RN(rstn_i)
  );
endmodule


module fpga_tech_buffer
  (input  i,
   output z);
  wire buf_X;
  assign z = buf_X;

  gf180mcu_fd_sc_mcu7t5v0__buf_1 tech_buf (
    .I(i),
    .Z(buf_X));
endmodule


module fpga_tech_clkbuffer
  (input  i,
   output z);
  wire buf_X;
  assign z = buf_X;
     
  gf180mcu_fd_sc_mcu7t5v0__clkbuf_1 tech_buf (
    .I(i),
    .Z(buf_X));
endmodule


module efuse_ctrl (wb_ack_o,
    wb_clk_i,
    wb_cyc_i,
    wb_rst_i,
    wb_sel_i,
    wb_stb_i,
    wb_we_i,
    wb_adr_i,
    wb_dat_i,
    wb_dat_o);
 output wb_ack_o;
 input wb_clk_i;
 input wb_cyc_i;
 input wb_rst_i;
 input wb_sel_i;
 input wb_stb_i;
 input wb_we_i;
 input [10:0] wb_adr_i;
 input [7:0] wb_dat_i;
 output [7:0] wb_dat_o;
endmodule
