module fpga_struct_block
  (input  clk_i,
   input  glb_rstn_i,
   input  config_clk_i,
   input  config_ena_i,
   input  config_shift_i,
   input  [31:0] inputs_up_i,
   input  [31:0] inputs_right_i,
   input  [31:0] inputs_down_i,
   input  [31:0] inputs_left_i,
   output config_shift_o,
   output [7:0] outputs_o);

endmodule
