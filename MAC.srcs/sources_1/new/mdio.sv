`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/07/2025 06:22:46 PM
// Design Name: 
// Module Name: mdio
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mdio # (
    parameter [4:0] PHY_ADDRESS = 5'b00001
)
(
    input clk,
    input resetn,

    // interface with MDIO
    input cmd_valid, // valid command to submit from source (whether read or write)
    output cmd_ready, // ready to submit commands
    
    input read_write, // read or /write command
    input [4:0] reg_adr, // register to read/write to

    input [15:0] write_data, // data to write from source

    output read_data_valid, // data is valid to read
    output [15:0] read_data, // data to read by source

    output mdc,
    inout mdio
);

// states
typedef enum logic [2:0] {
    IDLE,
    SETUP,
    DATA
} fsm_state_t;

fsm_state_t curr_state;
fsm_state_t next_state;

// output register
logic output_reg;
logic output_reg_0;

logic out_en;
logic out_en_reg;
logic _cmd_ready;
logic read_data_valid_reg;

// enable mdc
logic mdc_en;
logic mdc_en_reg;

// data and address of register to read/write from MDIO
logic [15:0] data;
logic read_write_reg;
logic [3:0] cbit;

// mdc clock generation
logic mdc_clk;
logic [2:0] mdc_clk_cnt;

// pulse high right before posedge and negedge of MDC clock
logic mdc_clk_pulse_pos;
logic mdc_clk_pulse_neg;

// mdio input synchronizer
reg mdio_in_ff1;
reg mdio_in_ff2;

// shift reg
logic [63:0] shift_reg;
logic [5:0] shift_cnt;
logic start_cnt;

// generate mdc clock (assuming input clock is 125mhz)
always_ff @(posedge clk) begin
    if (!resetn | !mdc_en_reg) begin
        mdc_clk <= 0;
        mdc_clk_cnt <= 0;
        mdc_clk_pulse_pos <= 0;
        mdc_clk_pulse_neg <= 0;
    end else begin
        if (mdc_clk_cnt == 4) begin
            mdc_clk <= ~mdc_clk;
            mdc_clk_cnt <= 0;
            mdc_clk_pulse_pos <= 0;
            mdc_clk_pulse_neg <= mdc_clk;
        end else if (mdc_clk_cnt == 3) begin
            mdc_clk_pulse_pos <= !mdc_clk;
            mdc_clk_pulse_neg <= 0;
            mdc_clk_cnt <= mdc_clk_cnt + 1;
        end else begin
            mdc_clk_pulse_pos <= 0;
            mdc_clk_pulse_neg <= 0;
            mdc_clk_cnt <= mdc_clk_cnt + 1;
        end
    end
end

// synchronous logic
always_ff @(posedge clk) begin
    if (!resetn) begin
        curr_state <= IDLE;
        cbit <= '0;
        data <= '0;
        output_reg <= 0;
        out_en_reg <= 0;
        mdc_en_reg <= 0;
        mdio_in_ff1 <= 0;
        mdio_in_ff2 <= 0;
        read_data_valid_reg <= 0;
        read_write_reg <= 0;
        shift_reg <= '0;
        shift_cnt <= '0;
        start_cnt <= 0;
        output_reg_0 <= 0;
    end else begin
        curr_state <= next_state;

        // register data to read/write
        if (_cmd_ready & cmd_valid) begin
            read_write_reg <= read_write;

            // preamble
            shift_reg[63:32] <= 32'hffff_ffff;
            // start
            shift_reg[31:30] <= 2'b01;

            // read_write low means we want to write data, so register the incoming data and opcode
            if (!read_write) begin
                // write opcode
                shift_reg[29:28] <= 2'b01;
                // reg data to write
                shift_reg[15:0] <= write_data;
            end else begin
                //read opcode
                shift_reg[29:28] <= 2'b10;
            end

            // phy address
            shift_reg[27:23] <= PHY_ADDRESS;

            // reg address
            shift_reg[22:18] <= reg_adr;

            // turnaround
            shift_reg[17:16] <= 2'b10;
        end else if (curr_state == IDLE) begin
            shift_reg <= '1;
        end

        if (curr_state == IDLE) begin
            start_cnt <= 0;
            shift_cnt <= 0;
        end else begin
            // count up and shift on mdc pulse
            if (mdc_clk_pulse_pos) begin
                start_cnt <= mdc_en_reg;
                shift_reg <= shift_reg << 1;

                // delay counting since one mdc cycle needs to happen before you increment to 1
                if (start_cnt) begin
                    shift_cnt <= shift_cnt + 1;
                end
            end
        end
        
        // set output reg to the shift reg MSB
        // pipeline it to meet setup/hold
        output_reg_0 <= shift_reg[63];
        output_reg <= output_reg_0;

        // register output from FSM
        mdc_en_reg <= mdc_en;
        out_en_reg <= out_en;

        // synchronize input
        if (!out_en_reg) begin
            mdio_in_ff1 <= mdio;
            mdio_in_ff2 <= mdio_in_ff1;
        end

        // if reading, register the data into read reg
        if (mdc_clk_pulse_neg & read_write_reg & !out_en_reg & shift_cnt > 47) begin
            cbit <= cbit - 1;
            data[cbit] <= mdio_in_ff2;
        end else if (shift_cnt <= 47) begin
            cbit <= 15;
        end

        if (mdc_clk_pulse_neg & shift_cnt == 63 & read_write_reg) begin
            read_data_valid_reg <= 1;
        end else if (!_cmd_ready) begin
            read_data_valid_reg <= 0;
        end
    end
end

// drive output depending on out_en, keep hi-z otherwise
assign mdio = (out_en_reg) ? output_reg : 1'bz;

// assign readys
assign read_data_valid = read_data_valid_reg;
assign cmd_ready = _cmd_ready;

// set read data to the data register, when reading we can change it and assert the ready
assign read_data = data;

// assign mdc as low when not in a frame
assign mdc = (mdc_en_reg) ? mdc_clk : 1'b0;

// next state comb logic
always_comb begin
    // default states
    mdc_en = 0;
    out_en = 0;
    next_state = curr_state;
    _cmd_ready = 0;

    unique case (curr_state)
        IDLE: begin
            out_en = 0;
            _cmd_ready = 1;
            mdc_en = 0;

            if (cmd_valid) begin
                next_state = SETUP;
            end
        end
        SETUP: begin
            mdc_en = 1;
            out_en = 1;
            
            if (shift_cnt == 45 & mdc_clk_pulse_neg) begin
                next_state = DATA;
            end        
        end
        DATA: begin
            mdc_en = 1;

            if (read_write_reg) begin
                out_en = 0;
            end else begin
                out_en = 1;
            end

            if (shift_cnt == 63 & mdc_clk_pulse_neg) begin
                next_state = IDLE;
            end
        end

        default: begin
            next_state = curr_state;
            mdc_en = 0;
            out_en = 0;
            _cmd_ready = 0;
        end
    endcase
end

endmodule
