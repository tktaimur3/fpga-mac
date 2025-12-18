`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/07/2025 03:18:49 PM
// Design Name: 
// Module Name: top
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


module top(
    input sys_clk_p,
    input sys_clk_n,
    input sys_rstn,
    output [5:0] led,
    output gphy_resetn,
    output gphy_mdc,
    inout gphy_mdio
);

    // 250Mhz clock generation
    // 200Mhz Diff clock -> IBBUFDS 200Mhz single-ended clock -> PLL 125Mhz clock
    wire clk_200mhz;
    IBUFDS #(
      .DIFF_TERM("FALSE"),       
      .IBUF_LOW_PWR("TRUE"),     
      .IOSTANDARD("DEFAULT")     
    ) IBUFDS_inst (
      .O(clk_200mhz),
      .I(sys_clk_p),
      .IB(sys_clk_n)
    );
    
    wire pll_locked;
    logic resetn;
    wire clk;
    clk_wiz_0 clk_inst (
        .clk_in1(clk_200mhz),
        .resetn(sys_rstn),     
        .clk_out1(clk),
        .locked(pll_locked)
    );

    assign resetn = pll_locked & sys_rstn;
    
    assign gphy_resetn = resetn;

    logic cmd_valid;
    wire cmd_ready;
    logic read_write;
    logic [4:0] reg_adr;
    logic [15:0] write_data;
    wire read_data_valid;
    wire [15:0] read_data;
    
    // data from PHY's BMSR reg
    logic read_bmsr_data_valid;
    logic [15:0] bmsr_reg_data;

    // data from PHY's PHYSR reg
    logic read_physr_data_valid;
    logic [15:0] physr_reg_data;


    mdio # (
        .PHY_ADDRESS(5'b00001)
    ) mdio_inst (
        .clk(clk),
        .resetn(resetn),
    
        // interface with MDIO
        .cmd_valid(cmd_valid), // valid command to submit from source (whether read or write)
        .cmd_ready(cmd_ready), // ready to submit commands
        
        .read_write(read_write), // read or /write command
        .reg_adr(reg_adr), // register to read/write to
    
        .write_data(write_data), // data to write from source (if writing)
    
        .read_data_valid(read_data_valid), // data is valid to read
        .read_data(read_data), // data to read by source
    
        .mdc(gphy_mdc),
        .mdio(gphy_mdio)
    );

    // states
    typedef enum logic [3:0] {
        SETUP,
        READ_BMSR,
        DISPLAY1,
        PAGE_SWITCH,
        WAIT_READY1,
        READ_PHYSR,
        WAIT_READY2,
        PAGE_SWITCH_STD,
        DISPLAY2
    } fsm_state_t;
    
    fsm_state_t curr_state;
    fsm_state_t next_state;
    
    always_ff @(posedge clk) begin
        if (!resetn) begin
            curr_state <= SETUP;
            bmsr_reg_data <= 0;
            physr_reg_data <= 0;
        end else begin
            curr_state <= next_state;
            
            // read data valid, so register this data
            if (read_data_valid & read_bmsr_data_valid) bmsr_reg_data <= read_data;

            if (read_data_valid & read_physr_data_valid) physr_reg_data <= read_data;
        end
    end
    
    // assign led bits based on read data
    
    // led0 is link status
    assign led[0] = bmsr_reg_data[2];
    
    // led1 is auto negotiation complete/not-complete
    assign led[1] = bmsr_reg_data[5];

    // led[2:3] is speed
    // 10: 1000Mbps 01: 100Mbps 00: 10Mbps
    assign led[2] = physr_reg_data[5];
    assign led[3] = physr_reg_data[4];

    always_comb begin
        next_state = curr_state;
        read_bmsr_data_valid = 0;
        read_physr_data_valid = 0;
        read_write = 0;
        reg_adr = 0;
        cmd_valid = 0;
        write_data = 0;

        case (curr_state)
            SETUP: begin
                if (cmd_ready) next_state = READ_BMSR;
            end
            READ_BMSR: begin                
                read_write = 1; // read
                reg_adr = 5'h01; // BMSR reg
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = DISPLAY1;
            end
            DISPLAY1: begin
                read_bmsr_data_valid = 1;

                if (cmd_ready) next_state = PAGE_SWITCH;
            end
            PAGE_SWITCH: begin                
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'ha43;
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = WAIT_READY1;
            end
            WAIT_READY1: begin
                if (cmd_ready) next_state = READ_PHYSR;
            end
            READ_PHYSR: begin                
                read_write = 1; // read
                reg_adr = 5'h1A; // PHYSR reg
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = DISPLAY2;
            end
           DISPLAY2: begin
                read_physr_data_valid = 1;

                if (cmd_ready) next_state = PAGE_SWITCH_STD;
            end
            PAGE_SWITCH_STD: begin                
                read_write = 0; // write
                reg_adr = 5'h1F; // PAGESEL reg
                write_data = 16'ha42; // back to default page
            
                cmd_valid = 1;
                
                if (!cmd_ready) next_state = WAIT_READY2;
            end
            WAIT_READY2: begin
                if (cmd_ready) next_state = SETUP;
            end
 
            
            default: begin
                next_state = curr_state;
                read_bmsr_data_valid = 0;
                read_physr_data_valid = 0;
                read_write = 0;
                reg_adr = 0;
                cmd_valid = 0;
                write_data = 0;
            end
        endcase
    end


endmodule
