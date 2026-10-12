FC = gfortran
FFLAGS ?= -O2 -Wall
LDFLAGS ?=
LDLIBS ?=
PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin
INSTALL ?= install

# Sources are listed in module dependency order.
SRCS = rho2cube/mod_utils.f90 \
       rho2cube/mod_pwmat_io.f90 \
       rho2cube/mod_cube.f90 \
       rho2cube/mod_corecharge.f90 \
       rho2cube/main.f90
TARGET = build/convert_rho2cube.x
TOOLS = $(wildcard tool/*.sh)

all: $(TARGET)

$(TARGET): $(SRCS) Makefile
	mkdir -p build
	$(FC) $(FFLAGS) $(LDFLAGS) -Jbuild -o $@ $(SRCS) $(LDLIBS)

test:
	$(MAKE) -C tests test

install: $(TARGET) $(TOOLS)
	$(INSTALL) -d "$(DESTDIR)$(BINDIR)"
	$(INSTALL) -m 755 "$(TARGET)" $(TOOLS) "$(DESTDIR)$(BINDIR)/"

clean:
	$(RM) build/*.mod $(TARGET)

clean-tests:
	$(MAKE) -C tests clean

.PHONY: all test clean clean-tests install
