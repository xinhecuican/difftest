#***************************************************************************************
# Copyright (c) 2020-2021 Institute of Computing Technology, Chinese Academy of Sciences
# Copyright (c) 2020-2021 Peng Cheng Laboratory
#
# XiangShan is licensed under Mulan PSL v2.
# You can use this software according to the terms and conditions of the Mulan PSL v2.
# You may obtain a copy of Mulan PSL v2 at:
#          http://license.coscl.org.cn/MulanPSL2
#
# THIS SOFTWARE IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OF ANY KIND,
# EITHER EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO NON-INFRINGEMENT,
# MERCHANTABILITY OR FIT FOR A PARTICULAR PURPOSE.
#
# See the Mulan PSL v2 for more details.
#***************************************************************************************

include config/verilator.mk

EMU_TOP      = SimTop

EMU_CSRC_DIR = $(abspath ./src/test/csrc)
EMU_CXXFILES = $(shell find $(EMU_CSRC_DIR) -name "*.cpp") $(SIM_CXXFILES) $(DIFFTEST_CXXFILES) $(PLUGIN_CXXFILES)
EMU_CXXFLAGS += -std=c++17 -static -Wall -I$(EMU_CSRC_DIR) -I$(SIM_CSRC_DIR) -I$(DIFFTEST_CSRC_DIR) -I$(PLUGIN_CHEAD_DIR)
EMU_CXXFLAGS += -DVERILATOR -DNUM_CORES=$(NUM_CORES) -DRV32
EMU_CXXFLAGS += $(shell sdl2-config --cflags) -fPIE
EMU_LDFLAGS  += -lpthread -lSDL2 -ldl -lz -lsqlite3

EMU_VFILES    = $(SIM_VSRC)

CCACHE := $(if $(shell which ccache),ccache,)
ifneq ($(CCACHE),)
export OBJCACHE = ccache
endif

VEXTRA_FLAGS  = -I$(abspath $(BUILD_DIR)) $(INCLUDE_DIRS) --x-assign unique -O3 -CFLAGS "$(EMU_CXXFLAGS)" -LDFLAGS "$(EMU_LDFLAGS)" -CFLAGS "\$$(PGO_CFLAGS)" -LDFLAGS "\$$(PGO_LDFLAGS)"

# Verilator version check
VERILATOR_VER_CMD = verilator --version 2> /dev/null | cut -f2 -d' ' | tr -d '.'
VERILATOR_4_210 := $(shell expr `$(VERILATOR_VER_CMD)` \>= 4210 2> /dev/null)
ifeq ($(VERILATOR_4_210),1)
EMU_CXXFLAGS += -DVERILATOR_4_210
VEXTRA_FLAGS += --instr-count-dpi 1
endif
VERILATOR_5_000 := $(shell expr `$(VERILATOR_VER_CMD)` \>= 5000 2> /dev/null)
ifeq ($(VERILATOR_5_000),1)
VEXTRA_FLAGS += --no-timing +define+VERILATOR_5
else
VEXTRA_FLAGS += +define+VERILATOR_LEGACY
endif
VERILATOR_5_024 := $(shell expr `$(VERILATOR_VER_CMD)` \>= 5024 2> /dev/null)
ifeq ($(VERILATOR_5_024),1)
VEXTRA_FLAGS += --quiet-stats
endif

# Verilator trace support
EMU_TRACE ?=
ifneq (,$(filter $(EMU_TRACE),1 vcd VCD))
VEXTRA_FLAGS += --trace --trace-structs
endif
ifneq (,$(filter $(EMU_TRACE),fst FST))
VEXTRA_FLAGS += --trace-fst --trace-structs
EMU_CXXFLAGS += -DENABLE_FST
endif

# Verilator multi-thread support
EMU_THREADS  ?= 0
ifneq ($(EMU_THREADS),0)
VEXTRA_FLAGS += --threads $(EMU_THREADS) --threads-dpi all
EMU_CXXFLAGS += -DEMU_THREAD=$(EMU_THREADS)
endif

# Verilator savable
EMU_SNAPSHOT ?=
ifeq ($(EMU_SNAPSHOT),1)
VEXTRA_FLAGS += --savable
EMU_CXXFLAGS += -DVM_SAVABLE
endif

# Verilator coverage
EMU_COVERAGE ?=
ifeq ($(EMU_COVERAGE),1)
VEXTRA_FLAGS += --coverage-line --coverage-toggle
endif

# co-simulation with DRAMsim3
ifeq ($(WITH_DRAMSIM3),1)
EMU_CXXFLAGS += -I$(DRAMSIM3_HOME)/src
EMU_CXXFLAGS += -DWITH_DRAMSIM3 -DDRAMSIM3_CONFIG=\\\"$(DRAMSIM3_HOME)/configs/DDR4_4Gb_x16_2400.ini\\\" -DDRAMSIM3_OUTDIR=\\\"$(BUILD_DIR)\\\"
EMU_LDFLAGS  += $(DRAMSIM3_HOME)/build/libdramsim3.a
endif

ifeq ($(DUALCORE),1)
EMU_CXXFLAGS += -DDUALCORE
endif

OPT_FAST ?= -O3

# --trace
VERILATOR_FLAGS =                   \
  --top-module $(EMU_TOP)           \
  --compiler clang 					\
  --no-timing 						\
  +define+VERILATOR=1               \
  +define+PRINTF_COND=1             \
  +define+RANDOMIZE_REG_INIT        \
  +define+RANDOMIZE_MEM_INIT        \
  +define+RANDOMIZE_GARBAGE_ASSIGN  \
  +define+RANDOMIZE_DELAY=0         \
  -Wno-STMTDLY -Wno-WIDTH           \
  $(VEXTRA_FLAGS)                   \
  --assert                          \
  --stats-vars                      \
  --output-split 30000              \
  --output-split-cfuncs 30000

EMU_DIR = $(BUILD_DIR)/emu-compile
EMU_MK := $(BUILD_DIR)/emu-compile/V$(EMU_TOP).mk
EMU_DEPS := $(EMU_VFILES) $(EMU_CXXFILES)
EMU_HEADERS := $(shell find $(EMU_CSRC_DIR) -name "*.h")     \
               $(shell find $(SIM_CSRC_DIR) -name "*.h")     \
               $(shell find $(DIFFTEST_CSRC_DIR) -name "*.h")

# Profile Guided Optimization
EMU_PGO_DIR  = $(EMU_DIR)/pgo
PGO_MAX_CYCLE ?= 2000000

EMU := $(BUILD_DIR)/emu

$(EMU_MK): $(EMU_DEPS)
	@mkdir -p $(@D)
	@echo "\n[verilator] Generating C++ files..." >> $(TIMELOG)
	@date -R | tee -a $(TIMELOG)
	@echo $^ >> $(TIMELOG)
	@echo "\n" >> $(TIMELOG)
	@echo $(EMU_DEPS) >> $(TIMELOG)
	$(TIME_CMD) verilator --cc --exe $(VERILATOR_FLAGS) \
		-o $(abspath $(EMU)) -Mdir $(@D)  $(EMU_DEPS) $(SRC)
ifneq ($(VERILATOR_5_000),1)
	find $(BUILD_DIR) -name "VSimTop.h" | xargs sed -i 's/private/public/g'
	find $(BUILD_DIR) -name "VSimTop.h" | xargs sed -i 's/const vlSymsp/vlSymsp/g'
	find $(BUILD_DIR) -name "VSimTop__Syms.h" | xargs sed -i 's/VlThreadPool\* const/VlThreadPool*/g'
endif

EMU_COMPILE_FILTER =
# 2> $(BUILD_DIR)/g++.err.log | tee $(BUILD_DIR)/g++.out.log | grep 'g++' | awk '{print "Compiling/Generating", $$NF}'

build_emu_local: $(EMU_MK)
	@echo "\n[g++] Compiling C++ files..." >> $(TIMELOG)
	@date -R | tee -a $(TIMELOG)
	$(TIME_CMD) $(MAKE) CXX=clang++ LINK=clang++  VM_PARALLEL_BUILDS=1 OPT_FAST=$(OPT_FAST) PGO_CFLAGS=$(PGO_CFLAGS) PGO_LDFLAGS=$(PGO_LDFLAGS) -C $(<D) -f $(<F) $(EMU_COMPILE_FILTER)

$(EMU): $(EMU_MK) $(EMU_DEPS) $(EMU_HEADERS) $(REF_SO)
ifeq ($(REMOTE),localhost)
ifdef PGO_WORKLOAD
	@echo "Building PGO profile..."
	@stat $(PGO_WORKLOAD) > /dev/null
	@$(MAKE) clean_obj
	@mkdir -p $(EMU_PGO_DIR)
	@sync -d $(BUILD_DIR) -d $(EMU_DIR)
	@$(MAKE) build_emu_local OPT_FAST=$(OPT_FAST) PGO_CFLAGS="-fprofile-generate=$(EMU_PGO_DIR)" PGO_LDFLAGS="-fprofile-generate=$(EMU_PGO_DIR)"
	@echo "Training emu with PGO Workload..."
	@sync -d $(BUILD_DIR) -d $(EMU_DIR)
	$(EMU) -i $(PGO_WORKLOAD) --max-cycles=$(PGO_MAX_CYCLE) B=0 E=0 1>$(EMU_PGO_DIR)/`date +%s`.log 2>$(EMU_PGO_DIR)/`date +%s`.err $(PGO_EMU_ARGS)
	@sync -d $(BUILD_DIR) -d $(EMU_DIR)
ifdef LLVM_PROFDATA
	$(LLVM_PROFDATA) merge $(EMU_PGO_DIR)/*.profraw -o $(EMU_PGO_DIR)/default.profdata
else
	@echo ""
	@echo "----------------------- NOTICE BEGIN -----------------------"
	@echo "If your verilator is compiled with LLVM, please don't forget"
	@echo "to add LLVM_PROFDATA=llvm-profdata when calling make."
	@echo ""
	@echo "If your verilator is compiled with GCC, please ignore this"
	@echo "message and NEVER adding LLVM_PROFDATA when calling make."
	@echo "----------------------- NOTICE  END  -----------------------"
	@echo ""
endif
	@echo "Building emu with PGO profile..."
	@$(MAKE) clean_obj
	@sync -d $(BUILD_DIR) -d $(EMU_DIR)
	@$(MAKE) build_emu_local OPT_FAST=$(OPT_FAST) PGO_CFLAGS="-fprofile-generate=$(EMU_PGO_DIR)" PGO_LDFLAGS="-fprofile-generate=$(EMU_PGO_DIR)"
else
	@echo "Building emu..."
	$(MAKE) build_emu_local OPT_FAST=$(OPT_FAST)
endif
else
	ssh -tt $(REMOTE) 'export NOOP_HOME=$(NOOP_HOME); export NEMU_HOME=$(NEMU_HOME); $(MAKE) -C $(NOOP_HOME)/difftest -j230 build_emu_local'
endif

# log will only be printed when (B<=GTimer<=E) && (L < loglevel)
# use 'emu -h' to see more details
B ?= 0
E ?= 0
WB ?= 0
WE ?= 0

EMU_FLAGS = -s $(SEED) -b $(B) -e $(E) -B $(WB) -E $(WE) $(SNAPSHOT_OPTION) $(WAVEFORM) $(EMU_ARGS)

emu: $(EMU)

emu-run: emu
ifneq ($(REMOTE),localhost)
	ls build
endif
	$(EMU) -i $(IMAGE) --diff=$(REF_SO) $(EMU_FLAGS)

LOG_ANNO_DIR = $(DESIGN_DIR)/build/annotated
coverage:
	verilator_coverage --annotate $(LOG_ANNO_DIR) --annotate-min 1 --write-info $(LOG_ANNO_DIR)/annotate.info $(DESIGN_DIR)/log/annotated.dat
	mkdir -p $(DESIGN_DIR)/log/annotate
	genhtml $(LOG_ANNO_DIR)/annotate.info -output-directory $(DESIGN_DIR)/log/annotate

clean_obj:
	rm -f $(EMU_DIR)/*.o $(EMU_DIR)/*.gch $(EMU_DIR)/*.a $(EMU_DIR)/*.d $(EMU)

.PHONY: build_emu_local
