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
TEST_SRCS = $(wildcard test_*.f90)
TEST_TARGETS = $(patsubst %.f90,$(BUILD_DIR)/%.x,$(TEST_SRCS))

test: $(TEST_TARGETS)
	@set -e; for test_bin in $(TEST_TARGETS); do "$$test_bin"; done

$(BUILD_DIR)/%.x: %.f90 $(MODULE_SRCS) Makefile
	mkdir -p $(BUILD_DIR)/$*
	$(FC) $(TEST_FFLAGS) $(LDFLAGS) -J$(BUILD_DIR)/$* -I$(BUILD_DIR)/$* -o $@ $(MODULE_SRCS) $< $(LDLIBS)

clean:
	$(RM) -r $(BUILD_DIR)

.PHONY: test clean
