# ibex-secure-boot (D2) master Makefile
#
#   make sim            all self-checking block testbenches (Icarus)
#   make sim-sha        SHA-256 core vs golden vectors
#   make sim-lifecycle  one-way lifecycle FSM, exhaustive
#   make sim-keystore   key store: CPU-invisibility + write-once + lock
#   make sim-measure    measured-boot chain vs software reference
#   make vectors        regenerate golden vectors (needs python3, no MATLAB)
#   make synth          OOC synth+P&R of the buildable blocks (Vivado)
#   make vm-synth       same, inside the Parallels Windows VM (Apple Silicon)
#   make waves T=sha    re-run one tb with +WAVES -> build/tb_<T>.vcd
#
# rot_top (full Ibex integration) is NOT built here yet -- see README.

IVERILOG ?= iverilog
VVP      ?= vvp
VIVADO   ?= vivado
PYTHON   ?= python3

RTL_DIR   = rtl
TB_DIR    = tb
BUILD_DIR = build
IVFLAGS   = -g2012 -Wall -Wno-timescale -I $(RTL_DIR)
PLUSARGS  = $(if $(WAVES),+WAVES,)

# tb name -> RTL sources it needs
SRC_sha       = $(RTL_DIR)/sha256_core.sv
SRC_lifecycle = $(RTL_DIR)/lifecycle_fsm.sv
SRC_keystore  = $(RTL_DIR)/key_store.sv
SRC_measure   = $(RTL_DIR)/measure_chain.sv $(RTL_DIR)/sha256_core.sv
TB_sha        = $(TB_DIR)/tb_sha256.sv
TB_lifecycle  = $(TB_DIR)/tb_lifecycle.sv
TB_keystore   = $(TB_DIR)/tb_key_store.sv
TB_measure    = $(TB_DIR)/tb_measure.sv
TOP_sha=tb_sha256
TOP_lifecycle=tb_lifecycle
TOP_keystore=tb_key_store
TOP_measure=tb_measure

TESTS = sha lifecycle keystore measure

.PHONY: all sim vectors synth vm-synth clean $(addprefix sim-,$(TESTS))
all: sim
$(BUILD_DIR): ; mkdir -p $(BUILD_DIR)

define RUN_TB
sim-$(1): | $(BUILD_DIR)
	$(IVERILOG) $(IVFLAGS) -s $(TOP_$(1)) -o $(BUILD_DIR)/tb_$(1).vvp $(SRC_$(1)) $(TB_$(1))
	@$(VVP) -N $(BUILD_DIR)/tb_$(1).vvp $(PLUSARGS) | tee $(BUILD_DIR)/tb_$(1).log
	@grep -q "TEST PASSED" $(BUILD_DIR)/tb_$(1).log
endef
$(foreach t,$(TESTS),$(eval $(call RUN_TB,$(t))))

sim: $(addprefix sim-,$(TESTS))
	@echo "=== all block testbenches passed: $(TESTS) ==="

waves:
	$(MAKE) sim-$(T) WAVES=1

vectors:
	$(PYTHON) vectors/nist_sha256/gen_vectors.py

synth:
	$(VIVADO) -mode batch -nolog -nojournal -source tcl/rot_synth.tcl -tclargs $(BLOCKS)

vm-synth:
	./scripts/vivado_in_parallels.sh $(BLOCKS)
	$(PYTHON) scripts/ppa_table.py

clean:
	rm -rf $(BUILD_DIR) vivado .Xil *.jou *.log
