module top (
    input sys_clk_p,
    input sys_clk_n,
    input sys_rstn,
    output [5:0] led,

    output gphy_txc,
    output gphy_txctl,
    output [3:0] gphy_txd,

    input gphy_rxc,

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

    // ------------------------------------------------------------
    // AXI Stream TX (MODULE -> MAC)
    // ------------------------------------------------------------
    wire        axi_tx_tvalid;
    wire        axi_tx_tlast;
    wire [7:0]  axi_tx_tdata;
    wire        axi_tx_tready;

    // ------------------------------------------------------------
    // AXI Stream RX (MAC -> MODULE)
    // ------------------------------------------------------------
    logic        axi_rx_tvalid;
    logic        axi_rx_tlast;
    logic [7:0]  axi_rx_tdata;
    logic        axi_rx_tready;

    // ------------------------------------------------------------
    // MAC inst
    // ------------------------------------------------------------
    mac # (
        .SRC_MAC_ADDRESS('{8'h02, 8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01}),
        .DST_MAC_ADDRESS('{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF})
    ) mac_inst (
        .clk            (clk),
        .resetn         (resetn),

        .axi_tx_tvalid  (axi_tx_tvalid),
        .axi_tx_tlast   (axi_tx_tlast),
        .axi_tx_tdata   (axi_tx_tdata),
        .axi_tx_tready  (axi_tx_tready),

        .axi_rx_tvalid  (axi_rx_tvalid),
        .axi_rx_tlast   (axi_rx_tlast),
        .axi_rx_tdata   (axi_rx_tdata),
        .axi_rx_tready  (axi_rx_tready),

        .rgmii_txd      (gphy_txd),
        .rgmii_txc      (gphy_txc),
        .rgmii_txctl    (gphy_txctl),

        .rgmii_rxd      (),
        .rgmii_rxc      (),
        .rgmii_rxctl    (),

        .mdc            (gphy_mdc),
        .mdio           (gphy_mdio),

        .led            (led)
    );

    data_stream # (
        .MSG_LEN(11),
        .MESSAGE("HE11O WORLD")
    ) data_stream_inst (
        .clk        (clk),
        .reset_n    (resetn),
        .tvalid     (axi_tx_tvalid),
        .tready     (axi_tx_tready),
        .tlast      (axi_tx_tlast),
        .char       (axi_tx_tdata)
    );

endmodule