# FPGA Ethernet MAC

A 1 Gbps Ethernet MAC implementation in SystemVerilog targeting the [Xilinx Artix-7 FPGA](https://www.en.puzhi.com/Product/AMD-FPGA-Development-Board/Artix-7/PA35T-StarLite). The design handles Ethernet frame TX over an RGMII interface and manages the external PHY via MDIO.

<img width="400" height="400" alt="image" src="https://github.com/user-attachments/assets/43093680-b95e-4c9b-8d55-91c1029a1449" />

## Features

- **RGMII TX** at 1 Gbps (125 MHz DDR using Xilinx ODDR primitives)
- **IEEE 802.3 frame construction**: preamble, SFD, destination/source MAC, EtherType/length, payload, FCS
- **CRC32** (ISO-HDLC / Ethernet polynomial) computed via 256-entry LUT
- **Minimum frame padding** to 46-byte payload per spec
- **Inter-frame gap** (12 cycles minimum)
- **MDIO PHY management**: PHY reset, TX delay enable, auto-negotiation restart, link status polling (BMSR/PHYSR)
- **AXI Stream slave interface** for TX data input
- Simulation/synthesis mode split via `` `ifdef SYNTHESIS `` — simulation skips link polling for faster iteration

## Architecture

```
data_stream ──AXI-S──> mac ──RGMII──> PHY
                        │
                    mdio_fsm ──> mdio ──MDIO──> PHY
```

| Module | File | Description |
|---|---|---|
| `top` | `src/top_mac.sv` | Top-level: clock generation (200 MHz diff → 125 MHz PLL), pin mapping |
| `mac` | `src/mac.sv` | TX FSM, ODDR clock forwarding, CRC32, MDIO orchestration |
| `mdio` | `src/mdio.sv` | MDIO serial controller, MDC clock generation (~12.5 MHz) |
| `mdio_fsm` | `src/mdio_fsm.sv` | PHY initialization and link-status polling FSM |
| `data_stream` | `src/data_stream.sv` | Parameterized test pattern generator (AXI Stream master) |

### MAC TX FSM

```
LINK_STATUS_POLL → IDLE → PREAMBLE → DESTINATION_ADDR → SOURCE_ADDR
    → LENGTH → DATA → [DATA_MIN] → CRC → FINISH → FRAME_GAP → (back to IDLE or PREAMBLE)
```

- `DATA_MIN`: zero-pads payload to the 46-byte minimum
- `LINK_STATUS_POLL`: polls MDIO until link is up and auto-negotiation is complete (synthesis only)

### MDIO FSM Sequence (on reset)

1. Write BMCR reset
2. Switch to page 0xD08, read TX delay register, set TX delay bit, write back
3. Switch to default page, restart auto-negotiation
4. Poll BMSR until link up + AN complete (reads twice per spec)
5. Switch to page 0xA43, poll PHYSR until link is 1 Gbps
6. Wait ~100 ms, assert `done`

After the first run the FSM loops back to just polling BMSR/PHYSR on each `start` pulse.

## Target Hardware

| Item | Value |
|---|---|
| Device | Xilinx Artix-7 `xc7a35tfgg484-2` |
| Input clock | 200 MHz differential (SSTL15) |
| MAC clock | 125 MHz (from PLL/`clk_wiz_0`) |
| PHY address | `0x01` |
| Default SRC MAC | `02:DE:AD:BE:EF:01` |
| Default DST MAC | `FF:FF:FF:FF:FF:FF` (broadcast) |
| Tool | Vivado 2025.1 |

## Repository Layout

```
src/            RTL source files
sim/            Testbenches (MAC and MDIO)
constr/         XDC pin constraints
ip/             Vivado IP (clk_wiz_0)
build_bit.tcl   Vivado batch build script
Makefile        Build targets
```

## Building

Requires Vivado 2025.1 on PATH.

```bash
make        # synthesize, implement, and generate bitstream
make clean  # remove all generated outputs
```

The bitstream is written to `MAC.runs/impl_1/top.bit`.

## Simulation

Open the project in Vivado and run the `testbench_mac` simulation, or use the generated scripts:

```
MAC.sim/sim_1/behav/xsim/simulate.bat
```

The `data_stream` module is parameterized with `MSG_LEN` and `MESSAGE` and sends up to `DATA_SENT_CNT` (20) frames before stopping. In simulation the MAC starts in `IDLE` instead of `LINK_STATUS_POLL`, so no MDIO traffic is needed to begin TX.

## Status & Roadmap

### Done

**TX path**
- Full IEEE 802.3 frame construction: preamble, SFD, dst/src MAC, EtherType/length, payload, FCS
- CRC32 (ISO-HDLC) computed byte-by-byte via a 256-entry LUT
- Minimum payload padding to 46 bytes (zero-fill)
- Inter-frame gap enforced (12 cycles minimum)
- Cut-through TX — data flows directly from AXI Stream to RGMII without buffering
- RGMII clock forwarding via ODDR primitive

**PHY management (MDIO)**
- PHY hard reset via BMCR on startup
- TX delay enable (read-modify-write to page 0xD08)
- Auto-negotiation restart
- Link polling: BMSR checked twice per spec, PHYSR checked for 1 Gbps confirmation
- Continuous link-status polling in the background while idle

### Future Work

**TX path**
- Store-and-forward buffer: the current cut-through design has no recovery path if `tready` drops mid-frame (e.g. link goes down). A FIFO-backed approach would let the MAC abort or retry gracefully.

**RX path**
- RGMII RX input capture (IDDR primitives for DDR sampling)
- Preamble and SFD stripping
- FCS validation and bad-frame rejection
- AXI Stream master output for received payload
