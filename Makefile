PROJECT = MAC

all:
	vivado -mode batch -source build_bit.tcl

clean:
	rm -rf $(PROJECT).runs \
	       $(PROJECT).sim \
	       $(PROJECT).cache \
		   $(PROJECT).hw \
	       $(PROJECT).ip_user_files \
	       $(PROJECT).srcs \
		   $(PROJECT).gen \
	       *.xpr *.jou *.log *.str timing.txt utilization.txt dfx_runtime.txt 