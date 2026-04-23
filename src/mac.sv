`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mac
// Description: Top-level Ethernet MAC. Instantiates the TX datapath (mac_tx),
//              RX datapath (mac_rx), and the MDIO management interface
//              (mdio_fsm + mdio) and wires link status between them.
//////////////////////////////////////////////////////////////////////////////////

module mac # (
    parameter [7:0] SRC_MAC_ADDRESS [0:5] = '{8'h02, 8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01},
    parameter [7:0] DST_MAC_ADDRESS [0:5] = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF}
)
(
    input clk,
    input resetn,

    // AXI Stream slave interface for transmitting data to PHY
    input        axi_tx_tvalid,
    input        axi_tx_tlast,
    input  [7:0] axi_tx_tdata,
    output       axi_tx_tready,

    // AXI Stream master interface for receiving data from PHY
    output       axi_rx_tvalid,
    output       axi_rx_tlast,
    output [7:0] axi_rx_tdata,
    input        axi_rx_tready,

    // RGMII for TX
    output [3:0] rgmii_txd,
    output       rgmii_txc,
    output       rgmii_txctl,

    // RGMII for RX
    input [3:0] rgmii_rxd,
    input       rgmii_rxc,
    input       rgmii_rxctl,

    // mdio
    output mdc,
    inout  mdio,

    // leds
    output [5:0] led
);

    // mdio interface signals
    wire        cmd_valid;
    wire        cmd_ready;
    wire        read_write;
    wire [4:0]  reg_adr;
    wire [15:0] write_data;
    wire        read_data_valid;
    wire [15:0] read_data;

    // link polling FSM interface
    logic        mdio_fsm_start;
    logic        mdio_fsm_done;
    logic        mdio_fsm_done_reg;
    logic [15:0] bmsr;
    logic [15:0] physr;

    // link status derived from BMSR (link up + auto-neg complete)
    logic link_up;
    assign link_up = bmsr[2] & bmsr[5];

    // TX status outputs (driven onto LEDs)
    logic txen_status;
    logic transmitting_status;

    always_ff @(posedge clk) begin
        if (!resetn) mdio_fsm_done_reg <= 0;
        else         mdio_fsm_done_reg <= mdio_fsm_done;
    end

    // MDIO FSM inst
    mdio_fsm mdio_fsm_inst (
        .clk                (clk),
        .resetn             (resetn),
        .start              (mdio_fsm_start),
        .done               (mdio_fsm_done),
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

        .led                (led)
    );

    // MDIO inst
    mdio # (
        .PHY_ADDRESS(5'b00001)
    ) mdio_inst (
        .clk(clk),
        .resetn(resetn),

        .cmd_valid(cmd_valid),              // valid command to submit from MAC
        .cmd_ready(cmd_ready),              // MDIO inst ready to submit commands

        .read_write(read_write),            // read or /write command
        .reg_adr(reg_adr),                  // register to read/write to

        .write_data(write_data),            // data to write from source (if writing)

        .read_data_valid(read_data_valid),  // data is valid to read
        .read_data(read_data),              // data to read by MAC

        .mdc(mdc),
        .mdio(mdio)
    );

    // MAC TX inst
    mac_tx # (
        .SRC_MAC_ADDRESS(SRC_MAC_ADDRESS),
        .DST_MAC_ADDRESS(DST_MAC_ADDRESS)
    ) mac_tx_inst (
        .clk                 (clk),
        .resetn              (resetn),

        .mdio_fsm_start      (mdio_fsm_start),
        .mdio_fsm_done       (mdio_fsm_done),
        .link_up             (link_up),

        .axi_tx_tvalid       (axi_tx_tvalid),
        .axi_tx_tlast        (axi_tx_tlast),
        .axi_tx_tdata        (axi_tx_tdata),
        .axi_tx_tready       (axi_tx_tready),

        .rgmii_txd           (rgmii_txd),
        .rgmii_txc           (rgmii_txc),
        .rgmii_txctl         (rgmii_txctl),

        .txen_status         (txen_status),
        .transmitting_status (transmitting_status)
    );

    // MAC RX inst (placeholder)
    mac_rx mac_rx_inst (
        .clk            (clk),
        .resetn         (resetn),

        .axi_rx_tvalid  (axi_rx_tvalid),
        .axi_rx_tlast   (axi_rx_tlast),
        .axi_rx_tdata   (axi_rx_tdata),
        .axi_rx_tready  (axi_rx_tready),

        .rgmii_rxd      (rgmii_rxd),
        .rgmii_rxc      (rgmii_rxc),
        .rgmii_rxctl    (rgmii_rxctl)
    );

    assign led[2] = mdio_fsm_start;
    assign led[3] = txen_status;
    assign led[4] = transmitting_status;
    assign led[5] = mdio_fsm_done_reg;

endmodule
