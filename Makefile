# Falcon FPGA accelerator - top-level entry points.
#
#   make lint                     Verilator lint of the RTL
#   make sim TB=ntt_512_tb        run one SV testbench in xsim (batch)
#   make test-sv                  run all self-checking SV testbenches
#   make project                  create the Vivado project in build/vivado (for GUI work)
#   make ip                       package the accelerator as an IP core into build/ip_repo
#   make bd N=1024                create the block design project in build/bd_<N>
#   make xsa N=1024               synthesize + implement the block design, write build/falcon_<N>.xsa
#   make sim-top ALG=verify1024   simulate the whole accelerator (instruction_dispatch_tb, slow)
#
# Vivado tools (vivado, xvlog, xelab, xsim) are taken from PATH.

SHELL := /bin/bash

VIVADO          := mkdir -p build && cd build && vivado -mode batch -nojournal -notrace

ROOT  := $(abspath .)
BUILD := $(ROOT)/build
N     ?= 512
# Data set for sim-top: one of mem/instruction_dispatch_tb/{sign512,sign1024,verify512,verify1024}
ALG   ?= sign512

# Testbench to run with `make sim`, and how long to run it (xsim time, or "all")
TB       ?= ntt_512_tb
SIM_TIME ?= all
# Extra defines for xvlog, e.g. DEFINES='FALCON_BRAM_INIT_DIR=\"$(ROOT)/mem/instruction_dispatch_tb/sign512\"'
DEFINES  ?=

# Self-checking testbenches (they $fatal on mismatch and $finish when done)
SV_TESTS := check_bound_tb compress_tb compress_coefficient_tb decompress_tb decompress_coefficient_tb \
            fft_512_tb fft_1024_tb ifft_512_tb ifft_1024_tb hash_to_point_tb merge_fft_tb split_fft_tb \
            mult_mod_q_tb mult_mod_q_for_ntt_tb ntt_512_tb ntt_1024_tb intt_512_tb intt_1024_tb

RTL_FILES := $(filter-out +incdir+%,$(shell cat rtl/files.f))

.PHONY: help lint sim test-sv sim-top project ip bd xsa clean

help:
	@sed -n '3,14p' Makefile | sed 's/^# //'

lint:
	verilator --lint-only -Wall -Wno-fatal -f rtl/files.f --top-module axi_wrapper

sim:
	@mkdir -p $(BUILD)/xsim/$(TB)
	@echo "xsim: $(TB) (logs in build/xsim/$(TB))"
	@cd $(BUILD)/xsim/$(TB) && \
	  xvlog -sv --nolog -i $(ROOT)/rtl/common \
	    -d FALCON_MEM_DIR=\"$(ROOT)/mem\" $(foreach d,$(DEFINES),-d $(d)) \
	    $(addprefix $(ROOT)/,$(RTL_FILES)) $(ROOT)/tb/sv/$(TB).sv >xvlog.log && \
	  xelab --nolog --relax -timescale 1ns/1ps -debug typical $(TB) -s $(TB) >xelab.log && \
	  echo "run $(SIM_TIME); quit" > run.tcl && \
	  xsim --nolog $(TB) -tclbatch run.tcl | tee xsim.log && \
	  grep -q '^\$$finish called' xsim.log && ! grep -q -E '^(Fatal|ERROR):' xsim.log

test-sv:
	@fail=0; for t in $(SV_TESTS); do \
	  if $(MAKE) --no-print-directory sim TB=$$t >/dev/null 2>&1; then echo "PASS $$t"; \
	  else echo "FAIL $$t  (see build/xsim/$$t/)"; fail=1; fi; \
	done; exit $$fail

# instruction_dispatch_tb hard-codes N=512 and algorithm_select=sign; edit them to match ALG
sim-top:
	$(MAKE) --no-print-directory sim TB=instruction_dispatch_tb \
	  DEFINES='FALCON_BRAM_INIT_DIR=\"$(ROOT)/mem/instruction_dispatch_tb/$(ALG)\"'

project:
	$(VIVADO) -source $(ROOT)/vivado/create_project.tcl -tclargs $(BUILD)/vivado

ip:
	$(VIVADO) -source $(ROOT)/vivado/package_ip.tcl -tclargs $(BUILD)/ip_repo

bd: ip
	$(VIVADO) -source $(ROOT)/vivado/create_bd_project.tcl -tclargs $(BUILD)/bd_$(N) $(BUILD)/ip_repo $(N)

xsa: ip
	$(VIVADO) -source $(ROOT)/vivado/build.tcl -tclargs $(BUILD)/bd_$(N) $(BUILD)/ip_repo $(N) $(BUILD)/falcon_$(N).xsa

clean:
	rm -rf $(BUILD) .Xil
