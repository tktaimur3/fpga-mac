`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/26/2025 11:06:56 AM
// Design Name: 
// Module Name: testbench_mac
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


module testbench_mdio;

    reg clk;
    reg resetn;
    reg cmd_valid;
    wire cmd_ready;
    reg read_write;
    reg [4:0] reg_adr;
    reg [15:0] write_data;
    wire read_data_valid;
    wire [15:0] read_data;
    wire mdc;
    wire mdio;

    reg [15:0] bmsr;
    reg [15:0] physr;
    wire done;

    logic mdio_fsm_start;

    // MDIO FSM inst
    mdio_fsm mdio_fsm_inst (
        .clk                (clk),
        .resetn             (resetn),
        .start              (mdio_fsm_start),
        .done               (done),
        .bmsr               (bmsr),
        .physr              (physr),

        // interface with MDIO
        .cmd_valid          (cmd_valid),
        .cmd_ready          (cmd_ready),

        .read_write         (read_write),
        .reg_adr            (reg_adr),

        .write_data         (write_data),

        .read_data_valid    (read_data_valid),
        .read_data          (read_data),

        .led                ()
    );

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
    
        .mdc(mdc),
        .mdio(mdio)
    );


    // Clock generation: 125 MHz (8 ns period)
    initial clk = 0;
    always #4 clk = ~clk;  // toggle every 4 ns -> 125 MHz

    initial begin   
        mdio_fsm_start = 0;
        resetn = 0;
        #80;            // hold reset for 80 ns
        resetn = 1;

        mdio_fsm_start = 1;
    end


    // reg mdio_reg;
    // assign mdio = mdio_reg;
    // initial begin
    //     // read test
    //     mdio_reg = 1'bz;
    //     cmd_valid = 0;
    //     resetn = 0;
    //     read_write = 1; // read cmd
    //     reg_adr = 4'h5;
        
    //     #80;            // hold reset for 80 ns
    //     resetn = 1;
    //     #16;
    //     cmd_valid = 1; // command is now valid
    //     #3908;
    //     cmd_valid = 0;
        
    //     // enough time has passed to issue another command
    //     #1244;

    //     // write test
    //     read_write = 0; // write cmd
    //     reg_adr = 4'h5;
    //     write_data = 16'hAA;
    //     #8;
    //     cmd_valid = 1; // command is now valid
    //     #16;
    //     cmd_valid = 0;
        
    //     // enough time has passed to issue another command
    //     #3908;
    //     #1244;
    //     read_write = 1; // read cmd
    //     reg_adr = 4'h5;
    //     #32;
    //     cmd_valid = 1;
    //     #32;
    //     cmd_valid = 0;
        
    // end

    // Simulation runtime
    initial begin
//        #200_000;   // run long enough (~200 us)
        // run until done
        @(posedge done);
        
        $finish;
    end
    
endmodule
