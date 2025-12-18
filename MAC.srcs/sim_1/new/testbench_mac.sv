`timescale 1ns/1ps

module testbench_mac;

    //`define CUTOFF_MODE

    // ------------------------------------------------------------
    // Clock / Reset
    // ------------------------------------------------------------
    logic clk;
    logic resetn;

    localparam CLK_PERIOD = 8ns; // 125 MHz

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;
    end

    // ------------------------------------------------------------
    // AXI Stream TX (TB -> DUT)
    // ------------------------------------------------------------
    logic        axi_tx_tvalid;
    logic        axi_tx_tlast;
    logic [7:0]  axi_tx_tdata;
    logic        axi_tx_tready;

    // ------------------------------------------------------------
    // AXI Stream RX (DUT -> TB)
    // ------------------------------------------------------------
    logic        axi_rx_tvalid;
    logic        axi_rx_tlast;
    logic [7:0]  axi_rx_tdata;
    logic        axi_rx_tready;

    // ------------------------------------------------------------
    // RGMII
    // ------------------------------------------------------------
    logic [3:0] rgmii_txd;
    logic       rgmii_txc;
    logic       rgmii_txctl;

    logic [3:0] rgmii_rxd;
    logic       rgmii_rxc;
    logic       rgmii_rxctl;

    // ------------------------------------------------------------
    // MDIO
    // ------------------------------------------------------------
    logic mdc;
    tri   mdio;

    assign mdio = 1'bz;

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    mac # (
        .SRC_MAC_ADDRESS('{8'h02, 8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01}),
        .DST_MAC_ADDRESS('{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF})
    ) dut (
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

        .rgmii_txd      (rgmii_txd),
        .rgmii_txc      (rgmii_txc),
        .rgmii_txctl    (rgmii_txctl),

        .rgmii_rxd      (rgmii_rxd),
        .rgmii_rxc      (rgmii_rxc),
        .rgmii_rxctl    (rgmii_rxctl),

        .mdc            (gphy_mdc),
        .mdio           (gphy_mdio)
    );

    // ------------------------------------------------------------
    // Defaults / Tie-offs
    // ------------------------------------------------------------
//    initial begin
//         axi_tx_tvalid = 0;
//         axi_tx_tdata  = 0;
//         axi_tx_tlast  = 0;

//        axi_rx_tready = 1'b1;

//        rgmii_rxd     = 4'h0;
//        rgmii_rxc     = 1'b0;
//        rgmii_rxctl   = 1'b0;
//    end

    // ------------------------------------------------------------
    // Continuous AXI-Stream packet sender
    // ------------------------------------------------------------
//    task automatic send_packet_continuous(
//        input byte payload[],
//        input int  payload_len
//    );
//        int byte_idx;
//        int total_bytes;
//        logic [15:0] total_len;

//        begin
//            total_len   = payload_len;
//            total_bytes = payload_len + 2;
//            byte_idx    = 0;

//            // Start frame
//            axi_tx_tvalid <= 1'b1;
//            axi_tx_tlast  <= 1'b0;

//            while (byte_idx < total_bytes) begin
//                // Drive data
//                if (byte_idx == 0)
//                    axi_tx_tdata <= total_len[15:8];
//                else if (byte_idx == 1)
//                    axi_tx_tdata <= total_len[7:0];
//            `ifdef CUTOFF_MODE
//                else if (byte_idx == 4)
//                    axi_tx_tvalid <= 1'b0;
//            `endif
//                else
//                    axi_tx_tdata <= payload[byte_idx - 2];

//                axi_tx_tlast <= (byte_idx == total_bytes - 1);

//                @(posedge clk);
//                if (axi_tx_tready) begin
//                    byte_idx++;
//                end
//            end

//            // Frame complete
//            @(posedge clk);
//            axi_tx_tvalid <= 1'b0;
//            axi_tx_tlast  <= 1'b0;
//            axi_tx_tdata  <= '0;
//        end
//    endtask

//    // ------------------------------------------------------------
//    // Test sequence
//    // ------------------------------------------------------------
//   initial begin
//        byte payload[];

//        @(posedge resetn);
//        repeat (5) @(posedge clk);

//        payload = new[6];
//        payload[0] = 8'hDE;
//        payload[1] = 8'hAD;
//        payload[2] = 8'hBE;
//        payload[3] = 8'hEF;
//        payload[4] = 8'hCA;
//        payload[5] = 8'hFE;

//        $display("[%0t] Starting packet transmit", $time);
//        send_packet_continuous(payload, payload.size());

//        repeat (200) @(posedge clk);
//        #200_000;

//       $finish;
//    end

    data_stream # (
        .MSG_LEN(11),
        .MESSAGE("HE11O WORLD")
    ) data_stream_inst (
        .clk        (clk),
        .reset_n    (resetn),
        .tvalid     (axi_tx_tvalid),
        .tready     (axi_tx_tready),
        .char       (axi_tx_tdata)
    );


    // ------------------------------------------------------------
    // Monitors
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (axi_tx_tvalid && axi_tx_tready) begin
            $display("[%0t] AXI-TX: data=0x%02x last=%0d",
                     $time, axi_tx_tdata, axi_tx_tlast);
        end
    end

    always @(posedge clk) begin
        if (axi_rx_tvalid && axi_rx_tready) begin
            $display("[%0t] AXI-RX: data=0x%02x last=%0d",
                     $time, axi_rx_tdata, axi_rx_tlast);
        end
    end

    always @(posedge rgmii_txc) begin
        $display("[%0t] RGMII-TX: txd=%b txctl=%b",
                 $time, rgmii_txd, rgmii_txctl);
    end

endmodule