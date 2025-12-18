`timescale 1ns/1ps

module data_stream_oneshot # (
    parameter MSG_LEN = 11,                             // length of message
    parameter [8*MSG_LEN-1:0] MESSAGE = "HELLO WORLD"   // default message
)(
    input clk,
    input reset_n,
    input tready,
    output tvalid,
    output [7:0] char
    );

    `define TOTAL_LEN (MSG_LEN+2)

    reg valid_reg;
    logic [7:0] char_reg;
    reg [7:0] message [0:MSG_LEN-1];
    reg [15:0] char_ptr;
    reg [15:0] len;

    genvar i;
        generate
          for (i=0; i<MSG_LEN; i=i+1) begin : gen_msg
            assign message[i] = MESSAGE[8*(MSG_LEN-i)-1 -: 8];
        end
    endgenerate
        
    always @(posedge clk) begin
        if (!reset_n) begin
            char_ptr <= 0;
            valid_reg <= 0;
            len <= MSG_LEN;
        end else begin
            // if tvalid (from us) and tready from downstream, character has been consumed, move pointer, also wait 2sec
            if (tvalid & tready) begin
                if (char_ptr < `TOTAL_LEN-1)
                    char_ptr <= char_ptr + 1;                
            end
            
            // valid only if char_ptr < MSG_LEN
            if (char_ptr < `TOTAL_LEN-1) begin
                valid_reg <= 1;
            end else begin
                valid_reg <= 0;
            end
        end
    end

    always_comb begin
        if (char_ptr == 0)              char_reg = len[15:8];
        else if (char_ptr == 1)         char_reg = len[7:0];
        else if (char_ptr < `TOTAL_LEN)  char_reg = message[char_ptr-2];
        else                            char_reg = 0;
    end
    
    assign tvalid = valid_reg;
    assign char = char_reg;
   
endmodule