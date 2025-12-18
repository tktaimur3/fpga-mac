`timescale 1ns/1ps

module mdio_fsm (
    input clk,
    input resetn,
    input start,
    output done,
    output [15:0] bmsr,
    output [15:0] physr,

    // interface with MDIO
    output logic cmd_valid,
    input cmd_ready,
    output logic read_write,
    output logic [4:0] reg_adr,
    output logic [15:0] write_data,
    input read_data_valid,
    input [15:0] read_data,

    output [5:0] led
);

    // this was figured out through trial and error tbh - 15_625_000 was the lowest I got with it working just barely consistently
    `define CLOCKS_ELAPSED (16_777_215)

    logic done_fsm;

    // data from PHY's BMSR reg
    logic read_bmsr_data_valid;
    logic [15:0] bmsr_reg_data;

    // data from PHY's PHYSR reg
    logic read_physr_data_valid;
    logic [15:0] physr_reg_data;

    // data from PHY's TX delay data reg
    logic read_tx_data_valid;
    logic [15:0] tx_reg_data;

    // counter
    logic [23:0] time_counter;

    // states
    typedef enum logic [4:0] {
        SETUP,
        SETUP_POLLING,
        WRITE_BMCR_RESET,
        READ_BMCR,
        BMCR_DATA_VALID,
        READ_BMSR,
        BSMR_DATA_VALID,
        PAGE_SWITCH,
        WAIT_READY_1,
        READ_PHYSR,
        WAIT_READY_2,
        PHYSR_DATA_VALID,
        PAGE_SWITCH_D08,
        WAIT_READY_3,
        READ_TX_DELAY,
        READ_TX_DATA_VALID,
        PAGE_SWITCH_D08_2,
        WAIT_READY_4,
        WRITE_TX_DELAY,
        WAIT_READY_5,
        PAGE_SWITCH_DEFAULT,
        PAGE_SWITCH_DEFAULT_2,
        WAIT_READY_6,
        RESTART_AN,
        READ_BMSR_2,
        BSMR_DATA_VALID_2,
        TIME_COUNT,
        WAIT_READY_7
    } fsm_state_t;
    
    fsm_state_t curr_state;
    fsm_state_t next_state;
    
    always_ff @(posedge clk) begin
        if (!resetn) begin
            curr_state <= SETUP;
            bmsr_reg_data <= 0;
            physr_reg_data <= 0;
            tx_reg_data <= 0;
            time_counter <= 0;
        end else begin
            curr_state <= next_state;
            
            // read data valid, so register this data
            if (read_data_valid & read_bmsr_data_valid)     bmsr_reg_data <= read_data;
            if (read_data_valid & read_physr_data_valid)    physr_reg_data <= read_data;
            if (read_data_valid & read_tx_data_valid)       tx_reg_data <= read_data;

            // set time counter to increment only in the right state
            if (curr_state == TIME_COUNT)   time_counter <= time_counter + 1;
            else                            time_counter <= 0;
        end
    end

    assign done = done_fsm;

    assign bmsr = bmsr_reg_data;
    assign physr = physr_reg_data;
    
    // assign led bits based on read data
    // led0 is link status
    assign led[0] = bmsr_reg_data[2];
    
    // led1 is auto negotiation complete/not-complete
    assign led[1] = bmsr_reg_data[5];

    // led[2:3] is speed
    // 10: 1000Mbps 01: 100Mbps 00: 10Mbps
    // assign led[2] = physr_reg_data[5];
    // assign led[3] = physr_reg_data[4];

    always_comb begin
        next_state = curr_state;
        read_bmsr_data_valid = 0;
        read_physr_data_valid = 0;
        read_tx_data_valid = 0;
        read_write = 0;
        reg_adr = 0;
        cmd_valid = 0;
        write_data = 16'h0000;
        done_fsm = 0;

        case (curr_state)
            // Start here on cold reset
            SETUP: begin
                if (cmd_ready & start) next_state = WRITE_BMCR_RESET;
            end
            WRITE_BMCR_RESET: begin
                read_write = 0; // write
                reg_adr = 5'h00; // BMCR reg
                write_data = 16'h8000; // PHY reset
                cmd_valid = 1;

                if (!cmd_ready) next_state = WAIT_READY_1;
            end
            WAIT_READY_1: begin
                if (cmd_ready) next_state = PAGE_SWITCH_D08;
            end

            // Enable TX delay (read -> modify -> write)
            PAGE_SWITCH_D08: begin
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'h0d08; // to 0xd08
                cmd_valid = 1;

                if (!cmd_ready) next_state = WAIT_READY_2;
            end
            WAIT_READY_2: begin
                if (cmd_ready) next_state = READ_TX_DELAY;
            end
            READ_TX_DELAY: begin
                read_write = 1; // read
                reg_adr = 5'h11; // reg that has TX delay
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = READ_TX_DATA_VALID;
            end
            READ_TX_DATA_VALID: begin
                read_tx_data_valid = 1;

                if (cmd_ready) next_state = PAGE_SWITCH_D08_2;
            end
            PAGE_SWITCH_D08_2: begin
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'h0d08; // to 0xd08
                cmd_valid = 1;

                if (!cmd_ready) next_state = WAIT_READY_3;
            end
            WAIT_READY_3: begin
                if (cmd_ready) next_state = WRITE_TX_DELAY;
            end
            WRITE_TX_DELAY: begin
                read_write = 0; // write
                reg_adr = 5'h11; // reg that has TX delay
                write_data = {tx_reg_data[15:9], 1'b1, tx_reg_data[7:0]}; // edit bit[8]
                cmd_valid = 1;

                if (!cmd_ready) next_state = WAIT_READY_4;
            end
            WAIT_READY_4: begin
                if (cmd_ready) next_state = PAGE_SWITCH_DEFAULT;
            end

            // Switch back to default page and restart auto negotiation
            PAGE_SWITCH_DEFAULT: begin
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'h0000; // back to default page
                cmd_valid = 1;

                if (!cmd_ready) next_state = WAIT_READY_5;
            end
            WAIT_READY_5: begin
                if (cmd_ready) next_state = RESTART_AN;
            end
            RESTART_AN: begin
                read_write = 0; // write
                reg_adr = 5'h00; // BMCR reg
                write_data = 16'h1200; // AN reset (keep AN enabled)
                cmd_valid = 1;

                if (!cmd_ready) next_state = READ_BMSR;
            end

            // Come back here after FSM has already started the first time (on reset)
            SETUP_POLLING: begin
                if (cmd_ready & start) next_state = READ_BMSR;
            end
            // Read BMSR twice (recommended apparently)
            READ_BMSR: begin
                read_write = 1; // read
                reg_adr = 5'h01; // BMSR reg
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = BSMR_DATA_VALID;
            end
            BSMR_DATA_VALID: begin
                read_bmsr_data_valid = 1;

                if (cmd_ready & bmsr_reg_data[5] & bmsr_reg_data[2]) next_state = READ_BMSR_2;
                else if (cmd_ready) next_state = READ_BMSR;
            end
            READ_BMSR_2: begin
                read_write = 1; // read
                reg_adr = 5'h01; // BMSR reg
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = BSMR_DATA_VALID_2;
            end
            BSMR_DATA_VALID_2: begin
                read_bmsr_data_valid = 1;

                if (cmd_ready & bmsr_reg_data[5] & bmsr_reg_data[2]) next_state = PAGE_SWITCH;
                else if (cmd_ready) next_state = READ_BMSR_2;
            end

            // Read PHYSR registers to make sure speed is right (1Gbps) and link is up
            // Speed is bits 5:4 and link status is bit 2
            PAGE_SWITCH: begin
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'h0a43;
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = WAIT_READY_6;
            end
            WAIT_READY_6: begin
                if (cmd_ready) next_state = READ_PHYSR;
            end
            READ_PHYSR: begin
                read_write = 1; // read
                reg_adr = 5'h1A; // PHYSR reg
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = PHYSR_DATA_VALID;
            end
            PHYSR_DATA_VALID: begin
                read_physr_data_valid = 1;

                if (cmd_ready & physr_reg_data[2] & physr_reg_data[5] & !physr_reg_data[4]) next_state = PAGE_SWITCH_DEFAULT_2;
                else if (cmd_ready) next_state = READ_PHYSR;
            end

            // Switch back to default page and wait 100ms
            PAGE_SWITCH_DEFAULT_2: begin
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'h0000; // back to default page
                cmd_valid = 1;

                if (!cmd_ready) next_state = TIME_COUNT;
            end
            TIME_COUNT: begin
                if (time_counter == `CLOCKS_ELAPSED) next_state = WAIT_READY_7;
            end

            WAIT_READY_7: begin
                done_fsm = 1;

                // Once we've gone through this state machine once we don't have to do the whole thing again
                if (cmd_ready) next_state = SETUP_POLLING;
            end
            
            default: begin
                next_state = curr_state;
                read_bmsr_data_valid = 0;
                read_physr_data_valid = 0;
                read_write = 0;
                reg_adr = 0;
                cmd_valid = 0;
                write_data = 16'h0000;
                done_fsm = 0;
            end
        endcase
    end

endmodule