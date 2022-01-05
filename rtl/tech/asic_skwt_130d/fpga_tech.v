module sky130_fd_sc_hd__dfrtp_2
  (input  CLK,
   input  D,
   input  RESET_B,
   output Q);
endmodule

module sky130_fd_sc_hd__buf_1
  (input  A,
   output X);
endmodule

module sky130_fd_sc_hd__clkbuf_1
  (input  A,
   output X);
endmodule

module fpga_tech_register
  (input  clk_i,
   input  rstn_i,
   input  config_i_rst_polarity,
   input  config_i_rst_value,
   input  data_i,
   output data_o);

  sky130_fd_sc_hd__dfrtp_2 register (
    .CLK(clk_i),
    .D( data_i ),
    .Q( data_o ),
    .RESET_B(rstn_i)
  );
endmodule


module fpga_tech_buffer
  (input  i,
   output z);
  wire buf_X;
  assign z = buf_X;

  sky130_fd_sc_hd__buf_1 tech_buf (
    .A(i),
    .X(buf_X));
endmodule


module fpga_tech_clkbuffer
  (input  i,
   output z);
   
  sky130_fd_sc_hd__clkbuf_1 tech_clkbuf (
    .A(i),
    .X(z));
endmodule
