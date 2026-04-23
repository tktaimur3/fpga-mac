`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: mac_rx
// Description: Ethernet MAC receive path. Placeholder - not yet implemented.
//////////////////////////////////////////////////////////////////////////////////

module mac_rx (
    input clk,
    input resetn,

    // AXI Stream master interface for receiving data from PHY
    output logic       axi_rx_tvalid,
    output logic       axi_rx_tlast,
    output logic [7:0] axi_rx_tdata,
    input              axi_rx_tready,

    // RGMII for RX
    input [3:0] rgmii_rxd,
    input       rgmii_rxc,
    input       rgmii_rxctl
);

    // TODO: implement RX path
    assign axi_rx_tvalid = 1'b0;
    assign axi_rx_tlast  = 1'b0;
    assign axi_rx_tdata  = 8'h00;

endmodule
