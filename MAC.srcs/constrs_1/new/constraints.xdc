set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE Yes [current_design]

# diff clock and reset button
set_property -dict {PACKAGE_PIN R4 IOSTANDARD DIFF_SSTL15} [get_ports sys_clk_p]
set_property -dict {PACKAGE_PIN R14 IOSTANDARD LVCMOS33} [get_ports sys_rstn]

# create clock from pll, pll knows the input clock is 200Mhz
#create_generated_clock -name clk -source [get_ports sys_clk_p] [get_ports clk_out1]

# 125 MHz
create_clock -name rgmii_clk -period 8 [get_ports gphy_txc]

# GPHY inputs
# MDIO
set_property -dict {PACKAGE_PIN T20 IOSTANDARD LVCMOS33} [get_ports {gphy_resetn}]
set_property -dict {PACKAGE_PIN T18 IOSTANDARD LVCMOS33} [get_ports {gphy_mdc}]
set_property -dict {PACKAGE_PIN N15 IOSTANDARD LVCMOS33} [get_ports {gphy_mdio}]

# RGMII TX
set_property -dict {PACKAGE_PIN P17 IOSTANDARD LVCMOS33} [get_ports {gphy_txc}]
set_property -dict {PACKAGE_PIN R16 IOSTANDARD LVCMOS33} [get_ports {gphy_txctl}]
set_property -dict {PACKAGE_PIN P19 IOSTANDARD LVCMOS33} [get_ports {gphy_txd[0]}]
set_property -dict {PACKAGE_PIN P16 IOSTANDARD LVCMOS33} [get_ports {gphy_txd[1]}]
set_property -dict {PACKAGE_PIN N17 IOSTANDARD LVCMOS33} [get_ports {gphy_txd[2]}]
set_property -dict {PACKAGE_PIN R17 IOSTANDARD LVCMOS33} [get_ports {gphy_txd[3]}]

set_property SLEW FAST [get_ports  gphy_txc]
set_property SLEW FAST [get_ports  gphy_txctl]
set_property SLEW FAST [get_ports {gphy_txd[*]}]

#leds
set_property -dict {PACKAGE_PIN J21 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J19 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN H19 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN K18 IOSTANDARD LVCMOS33} [get_ports {led[3]}]
set_property -dict {PACKAGE_PIN K19 IOSTANDARD LVCMOS33} [get_ports {led[4]}]
set_property -dict {PACKAGE_PIN L19 IOSTANDARD LVCMOS33} [get_ports {led[5]}]