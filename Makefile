PROJECT = test

all:
	vivado -mode batch -source build_bit.tcl

clean:
	rm -rf $(PROJECT)/$(PROJECT).runs \
	       $(PROJECT)/$(PROJECT).sim \
	       $(PROJECT)/$(PROJECT).cache \
	       *.jou *.log *.str