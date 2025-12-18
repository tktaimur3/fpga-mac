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
    PREAMBLE,
    ST,
    OP,
    PHYAD,
    REGAD,
    TA,
    DATA
} fsm_state_t;

fsm_state_t curr_state;
fsm_state_t next_state;

// output register
logic output_reg;
logic out;
logic out_en;
logic out_en_reg;
logic _cmd_ready;
logic read_data_valid_reg;

// enable mdc
logic mdc_en;
logic mdc_en_reg;

// data and address of register to read/write from MDIO
logic [4:0] address;
logic [15:0] data;
logic read_write_reg;
logic [3:0] cbit;

// preamble reg (count 32 bits)
logic [4:0] preamble;

// ST counter
logic st_cnt;

// OP counter
logic read_write_reg_cnt;

// TA counter
logic ta_reg_cnt;

// data count
logic [1:0] data_done;
logic data_start_read;

// mdc clock generation
logic mdc_clk;
logic [2:0] mdc_clk_cnt;

// pulse high right before posedge and negedge of MDC clock
logic mdc_clk_pulse_pos;
logic mdc_clk_pulse_neg;

// mdio input synchronizer
reg mdio_in_ff1;
reg mdio_in_ff2;

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

            mdc_clk_pulse_pos <= 1 & !mdc_clk;
            mdc_clk_pulse_neg <= 1 & mdc_clk;
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
        preamble <= '0;
        cbit <= '0;
        address <= '0;
        data_done <= '0;
        data <= '0;
        output_reg <= 0;
        read_write_reg_cnt <= 0;
        st_cnt <= 0;
        ta_reg_cnt <= 0;
        out_en_reg <= 0;
        mdc_en_reg <= 0;
        mdio_in_ff1 <= 0;
        mdio_in_ff2 <= 0;
        read_data_valid_reg <= 0;
        data_start_read <= 0;
        read_write_reg <= 0;
    end else begin
        curr_state <= next_state;

        // register data to read/write
        if (_cmd_ready & cmd_valid) begin
            address <= reg_adr;
            read_write_reg <= read_write;
            read_write_reg_cnt <= read_write;

            // read_write low means we want to write data, so register the incoming data
            if (!read_write) begin
                data <= write_data;
                read_data_valid_reg <= 0;
            end 
        end

        // register output from FSM
        output_reg <= out;
        mdc_en_reg <= mdc_en;
        out_en_reg <= out_en;

        if (curr_state == IDLE) begin
            preamble <= '0;
            data_done <= '0;
            data_start_read <= 0;
        end else if (curr_state == PREAMBLE) begin
            if (mdc_clk_pulse_pos) begin
                preamble <= preamble + 1;
            end
        end else if (curr_state == ST) begin
            cbit <= 4;
            if (mdc_clk_pulse_pos) st_cnt <= st_cnt + 1;
        end else if (curr_state == OP) begin
            if (mdc_clk_pulse_pos) read_write_reg_cnt <= read_write_reg_cnt + 1;
        end else if (curr_state == PHYAD | curr_state == REGAD) begin
            if (mdc_clk_pulse_pos) begin
                if (cbit > 0) begin
                    cbit <= cbit - 1;
                end else begin
                    cbit <= 4;
                end
            end
        end else if (curr_state == TA) begin
            // start off data_start_read with the correct value depending on whether we're reading or writing
            data_start_read <= !read_write_reg;
            
            read_data_valid_reg <= 0;
            if (mdc_clk_pulse_pos) ta_reg_cnt <= ta_reg_cnt + 1;
            cbit <= 15;
        end else if (curr_state == DATA) begin
            if (mdc_clk_pulse_pos) begin
                data_start_read <= 1;
            
                if (cbit > 0 & data_start_read) begin
                    cbit <= cbit - 1;
                end
            end else if (mdc_clk_pulse_neg) begin
                if (cbit == 0) begin
                    data_done <= data_done + 1;
                    
                    // update that read data is valid if we are instructed to read
                    read_data_valid_reg <= read_write_reg;
                end
            end

            // synchronize input
            if (!out_en_reg) begin
                mdio_in_ff1 <= mdio;
                mdio_in_ff2 <= mdio_in_ff1;
            end

            // sample data when reading it at negative edge after the first pos edge within DATA
            if (mdc_clk_pulse_neg & read_write_reg & data_start_read) begin
                data[cbit] <= mdio_in_ff2;
            end
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
    out = output_reg;
    next_state = curr_state;
    _cmd_ready = 0;

    unique case (curr_state)
        IDLE: begin
            out_en = 0;
            _cmd_ready = 1;
            out = 1;
            mdc_en = 0;

            if (cmd_valid) begin
                next_state = PREAMBLE;
            end
        end
        PREAMBLE: begin
            out_en = 1;
            out = 1;
            mdc_en = 1;

            if (preamble == 31 & mdc_clk_pulse_pos) begin
                next_state = ST;
            end
        end
        ST: begin
            out_en = 1;
            mdc_en = 1;
            out = st_cnt;

            if (mdc_clk_pulse_pos & st_cnt) begin
                next_state = OP;
            end
        end
        OP: begin
            out_en = 1;
            mdc_en = 1;
            out = read_write_reg_cnt;

            if (mdc_clk_pulse_pos & read_write_reg_cnt == ~read_write_reg) begin
                next_state = PHYAD;
            end
        end
        PHYAD: begin
            mdc_en = 1;
            out_en = 1;

            out = PHY_ADDRESS[cbit];

            if (cbit == 0 & mdc_clk_pulse_pos) begin
                next_state = REGAD;
            end
        end
        REGAD: begin
            mdc_en = 1;
            out_en = 1;

            out = address[cbit];

            if (cbit == 0 & mdc_clk_pulse_pos) begin
                next_state = TA;
            end
        end
        TA: begin
            mdc_en = 1;
            out = !ta_reg_cnt;
            out_en = !read_write_reg;
            
            if (mdc_clk_pulse_pos & ta_reg_cnt) begin
                next_state = DATA;
            end        
        end
        DATA: begin
            mdc_en = 1;

            if (read_write_reg) begin
                out_en = 0;
            end else begin
                out_en = 1;

                out = data[cbit];
            end

            if (cbit == 0 & data_done[!read_write_reg]) begin
                next_state = IDLE;
            end
        end

        default: begin
            next_state = curr_state;
            mdc_en = 0;
            out_en = 0;
            out = output_reg;
            _cmd_ready = 0;
        end
    endcase
end

endmodule
