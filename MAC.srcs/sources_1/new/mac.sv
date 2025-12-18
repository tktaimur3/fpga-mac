`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 11/13/2025 04:45:13 PM
// Design Name: 
// Module Name: mac
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

`define MIN_PAYLOAD_LEN (46)
`define PREAMBLE_LEN (8)
`define MAC_ADDR_LEN (6)
`define CRC_LEN (4)

module mac # (
    parameter [7:0] SRC_MAC_ADDRESS [0:5] = '{8'h02, 8'hDE, 8'hAD, 8'hBE, 8'hEF, 8'h01},
    parameter [7:0] DST_MAC_ADDRESS [0:5] = '{8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF, 8'hFF}
) 
(
    input clk,
    input resetn,

    // AXI Stream slave interface for transmitting data to PHY
    input axi_tx_tvalid,
    input axi_tx_tlast,
    input [7:0] axi_tx_tdata,
    output logic axi_tx_tready,

    // AXI Stream master interface for receiving data from PHY
    output axi_rx_tvalid,
    output axi_rx_tlast,
    output [7:0] axi_rx_tdata,
    input axi_rx_tready,

    // RGMII for TX
    output [3:0] rgmii_txd,
    output rgmii_txc,
    output rgmii_txctl,

    // RGMII for RX
    input [3:0] rgmii_rxd,
    input rgmii_rxc,
    input rgmii_rxctl,

    // mdio
    output mdc,
    inout mdio,

    // leds
    output [5:0] led
);

    // byte that inputs into ODDR
    logic [7:0] txd_reg;
    logic [7:0] txd;
    
    // ODDR clk enable
    logic oddr_clk_en_reg;
    logic oddr_clk_en;

    // mdio interface signals
    wire cmd_valid;
    wire cmd_ready;
    wire read_write;
    wire [4:0] reg_adr;
    wire [15:0] write_data;
    wire read_data_valid;
    wire [15:0] read_data;

    // link polling FSM interface
    logic mdio_fsm_start;
    logic mdio_fsm_done_reg;
    logic mdio_fsm_done;
    logic [15:0] bmsr;
    logic [15:0] physr;

    // link status registers
    logic [15:0] bmsr_reg;
    logic [15:0] physr_reg;

    // txctl
    logic txen;
    logic txerr;
    logic txen_reg;
    logic txerr_reg;

    // preamble count
    logic [2:0] preamble;
    
    // ip addr count
    logic [2:0] mac_addr;

    // data length
    logic [15:0] data_length;
    logic data_len_cnt;

    // data
    logic [15:0] data_cnt;

    // crc
    logic [1:0] crc_cnt;
    logic [31:0] crc_reg;
    logic [31:0] crc;

    // finish
    logic finish_cnt;

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

    // states
    typedef enum logic [3:0] {
        LINK_STATUS_POLL,
        IDLE,
        PREAMBLE,
        DESTINATION_ADDR,
        SOURCE_ADDR,
        LENGTH,
        DATA,
        CRC,
        FINISH
    } fsm_state_t;

    fsm_state_t curr_state;
    fsm_state_t next_state;

    // ODDR clock forward
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_inst (
        .Q(rgmii_txc),
        .C(clk),
        .CE(1'b1),
        .D1(1'b1),
        .D2(1'b0),
        .R(1'b0),
        .S(1'b0)
    );

    // assign rgmii_txc = clk;

    // ODDR TXCTL
    ODDR #(
        .DDR_CLK_EDGE("SAME_EDGE"),
        .INIT(1'b0),
        .SRTYPE("SYNC")
    ) ODDR_ctl_inst (
        .Q(rgmii_txctl),
        .C(clk),
        .CE(1'b1),
        .D1(txen_reg),
        .D2(txen_reg),
        .R(1'b0),
        .S(1'b0)
    );

    // ODDR output
    for (genvar i = 0; i < 4; i++) begin
        ODDR #(
            .DDR_CLK_EDGE("SAME_EDGE"),
            .INIT(1'b0),
            .SRTYPE("SYNC")
        ) ODDR_inst (
            .Q(rgmii_txd[i]),   // 1-bit DDR output
            .C(clk),            // 1-bit clock input
            .CE(1'b1),   // 1-bit clock enable input
            .D1(txd_reg[i]),    // 1-bit data input (positive edge)
            .D2(txd_reg[i+4]),  // 1-bit data input (negative edge)
            .R(1'b0),          // 1-bit reset
            .S(1'b0)
        );
    end

    logic oddr_reset;

    logic transmitting;

    logic mdio_fsm_done_reg_reg;

    always_ff @(posedge clk) begin
        if (!resetn) begin
        `ifndef SYNTHESIS
            curr_state <= IDLE;
        `else
            curr_state <= LINK_STATUS_POLL;
        `endif
            bmsr_reg <= 0;
            physr_reg <= 0;
            mdio_fsm_done_reg <= 0;
            preamble <= 0;
            mac_addr <= 0;
            data_length <= 0;
            data_len_cnt <= 0;
            data_cnt <= 0;
            txd_reg <= 0;
            oddr_clk_en_reg <= 0;
            crc_cnt <= 0;
            crc_reg <= 0;
            txen_reg <= 0;
            txerr_reg <= 0;
            finish_cnt <= 0;
            transmitting <= 0;
            mdio_fsm_done_reg_reg <= 0;
        end else begin
            curr_state <= next_state;
            mdio_fsm_done_reg <= mdio_fsm_done;
            txd_reg <= txd;
            oddr_clk_en_reg <= oddr_clk_en;
            txen_reg <= txen;
            txerr_reg <= txerr;

            if (mdio_fsm_done) begin
                bmsr_reg <= bmsr;
                physr_reg <= physr;
                mdio_fsm_done_reg_reg <= 1;
            end

            if (curr_state == IDLE | curr_state == LINK_STATUS_POLL) begin
                preamble <= 0;
                mac_addr <= 0;
                crc_cnt <= 0;
                data_cnt <= 0;
                crc_reg <= 32'hFFFFFFFF;
                finish_cnt <= 0;
                // transmitting <= 0;
            end if (curr_state == PREAMBLE) begin
                if (preamble == `PREAMBLE_LEN-1) begin
                    preamble <= 0;
                end else begin
                    preamble <= preamble + 1;
                end

            end else if (curr_state == DESTINATION_ADDR | curr_state == SOURCE_ADDR) begin
                crc_reg <= crc;

                if (mac_addr == `MAC_ADDR_LEN-1) begin
                    mac_addr <= 0;
                end else begin
                    mac_addr <= mac_addr + 1;
                end

            end else if (curr_state == LENGTH) begin
                crc_reg <= crc;

                if (axi_tx_tready & axi_tx_tvalid) begin
                    data_len_cnt <= data_len_cnt + 1;
                    
                    if (data_len_cnt == 0)  data_length[15:6] <= axi_tx_tdata;
                    else                    data_length[7:0]  <= axi_tx_tdata;
                end
            end else if (curr_state == DATA) begin
                data_cnt <= data_cnt + 1;
                crc_reg <= crc;
            end else if (curr_state == CRC) begin
                
                if (crc_cnt == `CRC_LEN-1) begin
                    crc_cnt <= 0;
                end else begin
                    crc_cnt <= crc_cnt + 1;
                end

                transmitting <= 1;
            end else if (curr_state == FINISH) begin
                finish_cnt <= finish_cnt + 1;
            end

        end
    end

    assign led[2] = mdio_fsm_start;
    assign led[3] = txen;
    assign led[4] = transmitting;
    assign led[5] = mdio_fsm_done_reg;

    always_comb begin
        next_state = curr_state;
        mdio_fsm_start = 0;
        axi_tx_tready = 0;
        oddr_clk_en = 0;
        txd = 0;
        oddr_reset = 0;
        txen = 0;
        txerr = 0;

        unique case (curr_state)
            LINK_STATUS_POLL: begin
                mdio_fsm_start = 1;
                oddr_reset = 1;

                // link status is up, auto-negotiation is complete, speed is 1Gbps, and FSM is done
                if (bmsr[2] & bmsr[5] & mdio_fsm_done) begin
                    next_state = IDLE;
                end
            end
            IDLE: begin
                oddr_reset = 1;

                // if no valid from upstream, poll the link
                if (axi_tx_tvalid) begin
                    next_state = PREAMBLE;
                end else begin
                    next_state = LINK_STATUS_POLL;
                end
            end
            PREAMBLE: begin
                oddr_clk_en = 1;
                txen = 1;
                txd = (preamble == `PREAMBLE_LEN-1) ? 8'hd5 : 8'h55;

                if (!axi_tx_tvalid) begin
                    next_state = FINISH;
                    txerr = 1;
                end else if (preamble == `PREAMBLE_LEN-1) begin
                    next_state = DESTINATION_ADDR;
                end
            end
            DESTINATION_ADDR: begin
                oddr_clk_en = 1;
                txen = 1;
                txd = DST_MAC_ADDRESS[mac_addr];
                
                if (!axi_tx_tvalid) begin
                    next_state = FINISH;
                    txerr = 1;
                end else if (mac_addr == `MAC_ADDR_LEN-1) begin
                    next_state = SOURCE_ADDR;
                end
            end
            SOURCE_ADDR: begin
                oddr_clk_en = 1;
                txen = 1;
                txd = SRC_MAC_ADDRESS[mac_addr];

                if (!axi_tx_tvalid) begin
                    next_state = FINISH;
                    txerr = 1;
                end else if (mac_addr == `MAC_ADDR_LEN-1) begin
                    next_state = LENGTH;
                end
            end
            LENGTH: begin
                oddr_clk_en = 1;
                axi_tx_tready = 1;
                txen = 1;
                txd = axi_tx_tdata;

                if (!axi_tx_tvalid) begin
                    next_state = FINISH;
                    txerr = 1;
                end else if (data_len_cnt == 1) begin 
                    next_state = DATA;
                end
            end
            DATA: begin
                // TODO: only handles IEEE 802.3 packet, not Ethernet II packet, handle data_length > 1536
                oddr_clk_en = 1;
                axi_tx_tready = (data_cnt < data_length);
                txen = 1;
                txd = (data_cnt < data_length) ? axi_tx_tdata : 8'h00;

                if ((data_cnt < data_length) & !axi_tx_tvalid) begin
                    next_state = FINISH;
                    txerr = 1;
                end else if (data_cnt == ((data_length >= `MIN_PAYLOAD_LEN) ? data_length-1 : `MIN_PAYLOAD_LEN-1)) begin
                    next_state = CRC;
                end
            end
            CRC: begin
                oddr_clk_en = 1;
                txen = 1;
                case (crc_cnt)
                    2'b00: txd = ~{crc_reg[4], crc_reg[5], crc_reg[6], crc_reg[7], crc_reg[0], crc_reg[1], crc_reg[2], crc_reg[3]};
                    2'b01: txd = ~{crc_reg[12], crc_reg[13], crc_reg[14], crc_reg[15], crc_reg[8], crc_reg[9], crc_reg[10], crc_reg[11]};
                    2'b10: txd = ~{crc_reg[20], crc_reg[21], crc_reg[22], crc_reg[23], crc_reg[16], crc_reg[17], crc_reg[18], crc_reg[19]};
                    2'b11: txd = ~{crc_reg[28], crc_reg[29], crc_reg[30], crc_reg[31], crc_reg[24], crc_reg[25], crc_reg[26], crc_reg[27]};
                endcase

                if (crc_cnt == `CRC_LEN-1) next_state = FINISH;
            end
            FINISH: begin
                oddr_clk_en = 1;
                // edge case: if axi_tx_tvalid comes back up during this time, txctl would be wrong
                // also if this happens after CRC this will probably be wrong, need "finish error" state
                // if (!axi_tx_tvalid) txerr = 1;

                if (finish_cnt == 1) begin
                `ifndef SYNTHESIS
                    next_state = IDLE;
                `else
                    next_state = IDLE;
                `endif
                end
            end

            default: begin
                next_state = curr_state;
                mdio_fsm_start = 0;
                axi_tx_tready = 0;
                oddr_clk_en = 0;
                txd = 0;
                oddr_reset = 0;
                txen = 0;
                txerr = 0;
            end
        endcase
    end

    // CRC32 LUT from https://crccalc.com/?crc=&method=CRC-32/ISO-HDLC
    logic [31:0] CRC32_LUT [0:255] = {  32'h00000000, 32'h77073096,  32'hEE0E612C, 32'h990951BA,   32'h076DC419, 32'h706AF48F,  32'hE963A535, 32'h9E6495A3,
                                        32'h0EDB8832, 32'h79DCB8A4,  32'hE0D5E91E, 32'h97D2D988,   32'h09B64C2B, 32'h7EB17CBD,  32'hE7B82D07, 32'h90BF1D91,
                                        32'h1DB71064, 32'h6AB020F2,  32'hF3B97148, 32'h84BE41DE,   32'h1ADAD47D, 32'h6DDDE4EB,  32'hF4D4B551, 32'h83D385C7,
                                        32'h136C9856, 32'h646BA8C0,  32'hFD62F97A, 32'h8A65C9EC,   32'h14015C4F, 32'h63066CD9,  32'hFA0F3D63, 32'h8D080DF5,
                                        32'h3B6E20C8, 32'h4C69105E,  32'hD56041E4, 32'hA2677172,   32'h3C03E4D1, 32'h4B04D447,  32'hD20D85FD, 32'hA50AB56B,
                                        32'h35B5A8FA, 32'h42B2986C,  32'hDBBBC9D6, 32'hACBCF940,   32'h32D86CE3, 32'h45DF5C75,  32'hDCD60DCF, 32'hABD13D59,
                                        32'h26D930AC, 32'h51DE003A,  32'hC8D75180, 32'hBFD06116,   32'h21B4F4B5, 32'h56B3C423,  32'hCFBA9599, 32'hB8BDA50F,
                                        32'h2802B89E, 32'h5F058808,  32'hC60CD9B2, 32'hB10BE924,   32'h2F6F7C87, 32'h58684C11,  32'hC1611DAB, 32'hB6662D3D,
                                        32'h76DC4190, 32'h01DB7106,  32'h98D220BC, 32'hEFD5102A,   32'h71B18589, 32'h06B6B51F,  32'h9FBFE4A5, 32'hE8B8D433,
                                        32'h7807C9A2, 32'h0F00F934,  32'h9609A88E, 32'hE10E9818,   32'h7F6A0DBB, 32'h086D3D2D,  32'h91646C97, 32'hE6635C01,
                                        32'h6B6B51F4, 32'h1C6C6162,  32'h856530D8, 32'hF262004E,   32'h6C0695ED, 32'h1B01A57B,  32'h8208F4C1, 32'hF50FC457,
                                        32'h65B0D9C6, 32'h12B7E950,  32'h8BBEB8EA, 32'hFCB9887C,   32'h62DD1DDF, 32'h15DA2D49,  32'h8CD37CF3, 32'hFBD44C65,
                                        32'h4DB26158, 32'h3AB551CE,  32'hA3BC0074, 32'hD4BB30E2,   32'h4ADFA541, 32'h3DD895D7,  32'hA4D1C46D, 32'hD3D6F4FB,
                                        32'h4369E96A, 32'h346ED9FC,  32'hAD678846, 32'hDA60B8D0,   32'h44042D73, 32'h33031DE5,  32'hAA0A4C5F, 32'hDD0D7CC9,
                                        32'h5005713C, 32'h270241AA,  32'hBE0B1010, 32'hC90C2086,   32'h5768B525, 32'h206F85B3,  32'hB966D409, 32'hCE61E49F,
                                        32'h5EDEF90E, 32'h29D9C998,  32'hB0D09822, 32'hC7D7A8B4,   32'h59B33D17, 32'h2EB40D81,  32'hB7BD5C3B, 32'hC0BA6CAD,
                                        32'hEDB88320, 32'h9ABFB3B6,  32'h03B6E20C, 32'h74B1D29A,   32'hEAD54739, 32'h9DD277AF,  32'h04DB2615, 32'h73DC1683,
                                        32'hE3630B12, 32'h94643B84,  32'h0D6D6A3E, 32'h7A6A5AA8,   32'hE40ECF0B, 32'h9309FF9D,  32'h0A00AE27, 32'h7D079EB1,
                                        32'hF00F9344, 32'h8708A3D2,  32'h1E01F268, 32'h6906C2FE,   32'hF762575D, 32'h806567CB,  32'h196C3671, 32'h6E6B06E7,
                                        32'hFED41B76, 32'h89D32BE0,  32'h10DA7A5A, 32'h67DD4ACC,   32'hF9B9DF6F, 32'h8EBEEFF9,  32'h17B7BE43, 32'h60B08ED5,
                                        32'hD6D6A3E8, 32'hA1D1937E,  32'h38D8C2C4, 32'h4FDFF252,   32'hD1BB67F1, 32'hA6BC5767,  32'h3FB506DD, 32'h48B2364B,
                                        32'hD80D2BDA, 32'hAF0A1B4C,  32'h36034AF6, 32'h41047A60,   32'hDF60EFC3, 32'hA867DF55,  32'h316E8EEF, 32'h4669BE79,
                                        32'hCB61B38C, 32'hBC66831A,  32'h256FD2A0, 32'h5268E236,   32'hCC0C7795, 32'hBB0B4703,  32'h220216B9, 32'h5505262F,
                                        32'hC5BA3BBE, 32'hB2BD0B28,  32'h2BB45A92, 32'h5CB36A04,   32'hC2D7FFA7, 32'hB5D0CF31,  32'h2CD99E8B, 32'h5BDEAE1D,
                                        32'h9B64C2B0, 32'hEC63F226,  32'h756AA39C, 32'h026D930A,   32'h9C0906A9, 32'hEB0E363F,  32'h72076785, 32'h05005713,
                                        32'h95BF4A82, 32'hE2B87A14,  32'h7BB12BAE, 32'h0CB61B38,   32'h92D28E9B, 32'hE5D5BE0D,  32'h7CDCEFB7, 32'h0BDBDF21,
                                        32'h86D3D2D4, 32'hF1D4E242,  32'h68DDB3F8, 32'h1FDA836E,   32'h81BE16CD, 32'hF6B9265B,  32'h6FB077E1, 32'h18B74777,
                                        32'h88085AE6, 32'hFF0F6A70,  32'h66063BCA, 32'h11010B5C,   32'h8F659EFF, 32'hF862AE69,  32'h616BFFD3, 32'h166CCF45,
                                        32'hA00AE278, 32'hD70DD2EE,  32'h4E048354, 32'h3903B3C2,   32'hA7672661, 32'hD06016F7,  32'h4969474D, 32'h3E6E77DB,
                                        32'hAED16A4A, 32'hD9D65ADC,  32'h40DF0B66, 32'h37D83BF0,   32'hA9BCAE53, 32'hDEBB9EC5,  32'h47B2CF7F, 32'h30B5FFE9,
                                        32'hBDBDF21C, 32'hCABAC28A,  32'h53B39330, 32'h24B4A3A6,   32'hBAD03605, 32'hCDD70693,  32'h54DE5729, 32'h23D967BF,
                                        32'hB3667A2E, 32'hC4614AB8,  32'h5D681B02, 32'h2A6F2B94,   32'hB40BBE37, 32'hC30C8EA1,  32'h5A05DF1B, 32'h2D02EF8D };

    // CRC generation
    // POLYNOMIAL: 0x04C11DB7
    // reflected input and output
    // init value: 0xFFFFFFFF
    // xor'd again with 0xFFFFFFFF
    always_comb begin
        crc = 0;

        if (curr_state == DESTINATION_ADDR | curr_state == SOURCE_ADDR | curr_state == LENGTH | curr_state == DATA) begin
            crc = (crc_reg >> 8) ^ CRC32_LUT[(crc_reg[7:0] ^ txd)];
        end
    end

endmodule
