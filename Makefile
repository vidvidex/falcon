# Falcon FPGA accelerator - top-level entry points.
#
#   make lint                     Verilator lint of the RTL
#   make test-sv                  run all SystemVerilog testbenches in xsim, in parallel
#   make project                  create the Vivado project in build/vivado (for GUI work)
#   make ip                       package the accelerator as an IP core into build/ip_repo
#   make bd N=1024                create the block design project in build/bd_<N>
#   make xsa N=1024               synthesize + implement the block design, write build/falcon_<N>.xsa
#
# Vivado tools (vivado, xvlog, xelab, xsim) are taken from PATH.

SHELL := /bin/bash

VIVADO := mkdir -p build && cd build && vivado -mode batch -nojournal -notrace

ROOT  := $(abspath .)
BUILD := $(ROOT)/build
N     ?= 512

RTL_FILES := $(filter-out +incdir+%,$(shell cat rtl/files.f))

# Module testbenches (tb/sv/*_tb.sv) and the whole-accelerator test (instruction_dispatch_tb), which runs once per
# data set in mem/instruction_dispatch_tb/. The accelerator tests take longest, so they are listed (and started) first.
MODULE_TESTS := $(filter-out instruction_dispatch_tb,$(notdir $(basename $(wildcard tb/sv/*_tb.sv))))
TOP_TESTS    := $(addprefix instruction_dispatch_tb_,sign512 sign1024 verify512 verify1024)
TESTS        ?= $(TOP_TESTS) $(MODULE_TESTS)
JOBS         ?= $(shell nproc)
# Simulated time limit per test; a test that has not finished by then fails (e.g. a hang after a design change)
SIM_TIME     ?= 20ms

RESULTS := $(patsubst %,$(BUILD)/xsim/%/result,$(TESTS))

.PHONY: help lint test-sv project ip bd xsa clean FORCE

help:
	@sed -n '3,8p' Makefile | sed 's/^# //'

lint:
	verilator --lint-only -Wall -Wno-fatal -f rtl/files.f --top-module axi_wrapper

test-sv:
	@rm -f $(RESULTS)
	@$(MAKE) --no-print-directory -k -j$(JOBS) $(RESULTS)
	@cat $(RESULTS) > $(BUILD)/test-results.txt; \
	  fail=$$(grep -c '^FAIL' $(BUILD)/test-results.txt); \
	  echo "$$(( $(words $(TESTS)) - fail )) passed, $$fail failed (of $(words $(TESTS))), results in build/test-results.txt"; \
	  [ $$fail -eq 0 ]

# $(call xsim,<testbench>,<xvlog options>,<xelab options>): compile and run a testbench in $(@D) and write PASS/FAIL to $@
define xsim
@mkdir -p $(@D)
@cd $(@D) && rm -f *.log && \
  if xvlog -sv --nolog -i $(ROOT)/rtl/common -d FALCON_MEM_DIR=\"$(ROOT)/mem\" $(2) \
       $(addprefix $(ROOT)/,$(RTL_FILES)) $(ROOT)/tb/sv/$(1).sv >xvlog.log 2>&1 && \
     xelab --nolog --relax -timescale 1ns/1ps -debug typical $(3) $(1) -s $(1) >xelab.log 2>&1 && \
     echo "run $(SIM_TIME); quit" > run.tcl && \
     xsim --nolog $(1) -tclbatch run.tcl >xsim.log 2>&1 && \
     grep -q '^\$$finish called' xsim.log && ! grep -q -E '^(Fatal|ERROR):' xsim.log; \
  then echo "PASS $(notdir $(@D))" | tee $(@F); \
  else echo "FAIL $(notdir $(@D))  see build/xsim/$(notdir $(@D))/" | tee $(@F); fi
endef

$(BUILD)/xsim/%/result: FORCE
	$(call xsim,$*)

# N and the algorithm (0 = sign, 1 = verify) are derived from the data set name
$(BUILD)/xsim/instruction_dispatch_tb_%/result: FORCE
	$(call xsim,instruction_dispatch_tb,-d FALCON_BRAM_INIT_DIR=\"$(ROOT)/mem/instruction_dispatch_tb/$*\",\
	  -generic_top N=$(subst sign,,$(subst verify,,$*)) -generic_top ALGORITHM=$(if $(filter verify%,$*),1,0))

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
