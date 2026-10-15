FC = gfortran
TEST_FFLAGS ?= -O0 -g -Wall -Wextra -fcheck=all
LDFLAGS ?=
LDLIBS ?=
BUILD_DIR = ../build/tests

# Sources are listed in module dependency order.
MODULE_SRCS = ../rho2cube/mod_utils.f90 \
              ../rho2cube/mod_pwmat_io.f90 \
              ../rho2cube/mod_cube.f90 \
              ../rho2cube/mod_corecharge.f90
CLI_SRCS = $(MODULE_SRCS) ../rho2cube/main.f90
CLI_TARGET = $(BUILD_DIR)/convert_rho2cube.x
TEST_SRCS = $(wildcard test_*.f90)
TEST_TARGETS = $(patsubst %.f90,$(BUILD_DIR)/%.x,$(TEST_SRCS))

# Run from tests/: read fixed inputs from data/, write artifacts only to
# TEST_WORK_DIR (a separate directory for each test). Fixed inputs are supplied
# separately; make test never creates or updates them. Keep runtime artifacts
# until make clean-tests.
test: $(CLI_TARGET) $(TEST_TARGETS)
	@set -e; status=0; \
	for test_bin in $(TEST_TARGETS); do \
		test_name=$${test_bin##*/}; test_name=$${test_name%.x}; \
		work_dir="$(abspath $(BUILD_DIR)/work)/$$test_name"; \
		mkdir -p "$$work_dir"; \
		RHO2CUBE_EXE="$(abspath $(CLI_TARGET))" \
		TEST_WORK_DIR="$$work_dir" "$$test_bin" || status=1; \
	done; exit $$status

$(CLI_TARGET): $(CLI_SRCS) Makefile
	mkdir -p $(BUILD_DIR)/cli
	$(FC) $(TEST_FFLAGS) $(LDFLAGS) -J$(BUILD_DIR)/cli -I$(BUILD_DIR)/cli -o $@ $(CLI_SRCS) $(LDLIBS)

$(BUILD_DIR)/%.x: %.f90 $(MODULE_SRCS) Makefile
	mkdir -p $(BUILD_DIR)/$*
	$(FC) $(TEST_FFLAGS) $(LDFLAGS) -J$(BUILD_DIR)/$* -I$(BUILD_DIR)/$* -o $@ $(MODULE_SRCS) $< $(LDLIBS)

clean:
	$(RM) -r $(BUILD_DIR)

.PHONY: test clean
