module $__FPGA_RAM1K (
    output [7:0] A1DATA,
    input        CLK1, A1EN,
    input  [8:0] A1ADDR,
    input        B1EN,
    input  [8:0] B1ADDR,
    input  [7:0] B1DATA
);
    parameter integer READ_MODE = 0;
    parameter integer WRITE_MODE = 0;
    parameter [0:0] NEGCLK_R = 0;
    parameter [0:0] NEGCLK_W = 0;

    fpga_memory _TECHMAP_REPLACE_ 
    (
        .clk_i(CLK1),
        
        .ce_a_i(A1EN),
        .addr_a_i(A1ADDR),
        .data_a_o(A1DATA),
        
        .we_b_i(B1EN),
        .addr_b_i(B1ADDR),
        .data_b_i(B1DATA)
    );
    
endmodule