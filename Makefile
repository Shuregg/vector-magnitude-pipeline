# Project Configuration
TOP_MODULE      := tb_vec_mag_top
WORKLIB         := work

export TOP_MODULE

# Flags
GUI=0
COV=0
SEED=random

# Tool Configuration
XRUN            := xrun
XRUN_OPTS       := -access +rw -clean -seed $(SEED) -disable_sem2009 -timescale 1ns/1ps -nowarn  SVECSZ -nowarn CUVWSI

# Simulation target with GUI option
ifeq ($(GUI), 1)
	XRUN_OPTS += -gui
endif

ifeq ($(COV), 1)
	XRUN_OPTS += -coverage all
endif

# Paths
ROOT_DIR := $(abspath ./ )
RTL_PATH         := $(ROOT_DIR)/rtl
DV_PATH          := $(ROOT_DIR)/dv
TB_PATH          := $(DV_PATH)/tb

export RTL_PATH
export TB_PATH
export DV_PATH

# Filelists
FILES_TB        := $(TB_PATH)/FILES_TB.f
FILES_RTL		:= $(RTL_PATH)/FILES_RTL.f

# Default target
all: compile elaborate

# Compilation target
compile:
	$(XRUN) \
		-compile \
		$(XRUN_OPTS) \
		$(XDEFINES) \
		-f $(FILES_RTL) \
		-f $(FILES_TB) \
		-top $(TOP_MODULE)

# Elaboration target
elaborate:
	$(XRUN) \
		-elaborate \
		$(XRUN_OPTS) \
		$(XDEFINES) \
		-f $(FILES_RTL) \
		-f $(FILES_TB) \
		-top $(TOP_MODULE)

sim: compile
	$(XRUN) \
		$(XRUN_OPTS) \
		$(XDEFINES) \
		-f $(FILES_RTL) \
		-f $(FILES_TB) \
		-top $(TOP_MODULE) \
		-input $(TB_PATH)/waves.tcl

# View waveforms with simvision
view:
	simvision waves.shm &

# Coverage targets
coverage: compile
	$(XRUN) \
		$(XRUN_OPTS) \
		$(XDEFINES) \
		-f $(FILES_RTL) \
		-f $(FILES_TB) \
		-top $(TOP_MODULE) \
		-coverage all \
		-covoverwrite \
		-input $(TB_PATH)/cov.tcl

# Clean targets
clean:
	rm -rf $(WORKLIB) xrun.log xrun.history .simvision xcelium.d

clean_all: clean
	rm -rf *.log *.vcd *.fsdb *.trn *.key *.shm *.vpd cov_work waves.shm

# Help target
help:
	@echo "Available targets:"
	@echo "  all        - Compile and elaborate"
	@echo "  compile    - Compile the design"
	@echo "  elaborate  - Elaborate the design"
	@echo "  sim        - Run simulation (batch mode)"
	@echo "  sim GUI=1  - Run simulation with GUI"
	@echo "  view       - View waveforms with simvision"
	@echo "  coverage   - Run with coverage collection"
	@echo "  clean      - Clean simulation artifacts"
	@echo "  clean_all  - Clean all generated files"
	@echo "  help       - Show this help message"
	@echo ""
	@echo "Filelists:"
	@echo "  RTL:  $(FILES_RTL)"
	@echo "  TB:   $(FILES_TB)"
	@echo ""
	@echo "Usage examples:"
	@echo "  make sim                    # Batch simulation"
	@echo "  make sim GUI=1              # GUI simulation"
	@echo "  make view                   # View waveforms"
	@echo "  make sim COV=1              # Run with coverage"

.PHONY: all compile elaborate sim view coverage clean clean_all help
