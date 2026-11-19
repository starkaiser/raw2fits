# raw2fits - camera RAW to FITS converter (Fortran 2018 + LibRaw)
#
#   make                    build ./raw2fits with the OpenMP thread backend (raw2fits -j N)
#   make BACKEND=coarray    build ./raw2fits-caf with the coarray backend (cafrun -n N, N >= 2)
#   make check              self-tests and a parallel run of the selected backend
#   make debug              build with run-time checks (-g -fcheck=all)
#   make install            install to $(PREFIX) (default /usr/local; use sudo)
#   make release            portable package for this OS, in dist/:
#                           Linux AppImage, macOS / FreeBSD tarball, Windows .exe
#   make release-windows    single raw2fits.exe (MinGW-w64 cross build on Linux,
#                           or native in an MSYS2 UCRT64 shell)
#   make clean              remove build products (distclean: also dist/ and LibRaw)
#   make help               show this list and the current configuration
#
# GNU make is required (on FreeBSD: gmake).
#
# The two backends are two implementations of the same module, m_workers:
#   src/convert/m_workers_threads.f90   OpenMP threads, one process; links LibRaw's
#                                       thread-safe libraw_r. Default; all releases.
#   src/convert/m_workers_coarray.f90   coarray images via OpenCoarrays/MPI. With
#                                       Debian/Ubuntu's OpenMPI 4.1 a coarray program
#                                       aborts in MPI_Win_create as a single image,
#                                       so start it with at least two images.

VERSION := $(strip $(shell cat VERSION 2>/dev/null))
ifeq ($(VERSION),)
  VERSION := dev
endif
.DEFAULT_GOAL := all

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
MANDIR  ?= $(PREFIX)/share/man/man1
DESTDIR ?=

# ---------------------------------------------------------------- platform
UNAME_S := $(shell uname -s 2>/dev/null)
ifneq ($(findstring MINGW,$(UNAME_S))$(findstring MSYS,$(UNAME_S))$(findstring CYGWIN,$(UNAME_S)),)
  HOST_PLATFORM := windows
else ifeq ($(UNAME_S),Darwin)
  HOST_PLATFORM := macos
else ifeq ($(UNAME_S),FreeBSD)
  HOST_PLATFORM := freebsd
else
  HOST_PLATFORM := linux
endif

# --------------------------------------------------------------- toolchain
# gfortran: plain name first, then versioned names (FreeBSD: gfortran13 ...).
ifndef GFORTRAN
  GFORTRAN := $(firstword $(foreach c,gfortran gfortran-15 gfortran15 gfortran-14 gfortran14 \
                gfortran-13 gfortran13 gfortran-12 gfortran12 gfortran-11 gfortran11, \
                $(shell command -v $(c) 2>/dev/null)))
  ifeq ($(GFORTRAN),)
    GFORTRAN := gfortran
  endif
endif
CAF        ?= caf
CAFRUN     ?= cafrun
PKG_CONFIG ?= pkg-config
ifeq ($(origin CC),default)
  CC := $(if $(shell command -v gcc 2>/dev/null),gcc,cc)
endif
STRIP ?= strip
EXE   ?=

BUILD ?= release
ifeq ($(BUILD),debug)
  OPT := -O0 -g -fcheck=all -fbacktrace
else
  OPT := -O2
endif

FFLAGS  ?= $(OPT) -std=f2018 -Wall -Wextra -Wimplicit-interface -Wno-maybe-uninitialized
CFLAGS  ?= $(OPT) -std=c11 -Wall -Wextra
LDFLAGS ?=

# Portable release builds (make release-*) override the settings above.
ifneq ($(RELEASE),)
  include packaging/release.mk
endif

# ----------------------------------------------------------------- backend
BACKEND ?= threads
ifeq ($(BACKEND),threads)
  FC_BUILD     := $(GFORTRAN)
  COARRAY_FLAG := -fcoarray=single
  OMP_FLAG     := -fopenmp
  LIBRAW_PC    := libraw_r
  PROGRAM_BIN  ?= raw2fits$(EXE)
else ifeq ($(BACKEND),coarray)
  ifeq ($(shell command -v $(CAF) 2>/dev/null),)
    $(error BACKEND=coarray needs OpenCoarrays' '$(CAF)': sudo apt install libcoarrays-openmpi-dev openmpi-bin)
  endif
  FC_BUILD     := $(CAF)
  COARRAY_FLAG := -fcoarray=lib
  OMP_FLAG     :=
  LIBRAW_PC    := libraw
  PROGRAM_BIN  ?= raw2fits-caf
else
  $(error BACKEND must be threads or coarray (got '$(BACKEND)'))
endif

ifndef LIBRAW_CFLAGS
  LIBRAW_CFLAGS := $(shell $(PKG_CONFIG) --cflags $(LIBRAW_PC) 2>/dev/null)
endif
ifndef LIBRAW_LIBS
  LIBRAW_LIBS := $(shell $(PKG_CONFIG) --libs $(LIBRAW_PC) 2>/dev/null || \
                   echo $(if $(OMP_FLAG),-lraw_r -lpthread,-lraw))
endif
LIBRAW_CHECK ?= yes

ALL_FFLAGS := $(FFLAGS) $(COARRAY_FLAG) $(OMP_FLAG)
CPPDEFS    := -DR2F_VERSION='"$(VERSION)"' -DR2F_BACKEND='"$(BACKEND)"'

VPATH := src src/cli src/convert src/raw src/output src/platform src/util tests

# ------------------------------------------------------------------ objects
UTIL_OBJ     := m_config.o m_log.o m_strings.o m_time.o
PLATFORM_OBJ := m_platform.o r2f_platform.o
RAW_OBJ      := m_frame.o m_pixel_ops.o
OUTPUT_OBJ   := m_fits_header.o m_metadata.o m_bytes.o m_fits_writer.o m_tiff_writer.o \
                m_pgm_writer.o m_output.o
CLI_OBJ      := m_options.o
LIBRAW_OBJ   := m_libraw.o m_raw.o r2f_libraw.o
CONVERT_OBJ  := m_jobs.o m_workers_$(BACKEND).o
MAIN_OBJ     := raw2fits.o

# Everything the self-tests need: no LibRaw, no worker backend.
TEST_OBJ := $(UTIL_OBJ) $(PLATFORM_OBJ) $(RAW_OBJ) $(OUTPUT_OBJ) $(CLI_OBJ)
PROG_OBJ := $(TEST_OBJ) $(LIBRAW_OBJ) $(CONVERT_OBJ) $(MAIN_OBJ)

OBJDIR     ?= build/$(BUILD)-$(BACKEND)
TEST_BIN   ?= $(OBJDIR)/test_raw2fits$(EXE)
EXTRA_OBJS ?=
LIBRAW_DEP ?=

# ------------------------------------------------------------------ targets
.PHONY: all debug check test check-unit check-threads check-coarray install uninstall \
        clean distclean dist help release release-linux release-macos \
        release-freebsd release-windows

all: $(PROGRAM_BIN)

$(PROGRAM_BIN): $(addprefix $(OBJDIR)/,$(PROG_OBJ)) $(EXTRA_OBJS) $(LIBRAW_DEP)
	$(FC_BUILD) $(ALL_FFLAGS) $(LDFLAGS) $(filter %.o,$^) $(LIBRAW_LIBS) -lm -o $@
	@echo "Built $@ ($(BACKEND) backend, $(BUILD), version $(VERSION))"

debug:
	$(MAKE) BUILD=debug

$(TEST_BIN): $(addprefix $(OBJDIR)/,$(TEST_OBJ) test_raw2fits.o)
	$(FC_BUILD) $(ALL_FFLAGS) $(LDFLAGS) $^ -o $@

# The self-tests use no coarrays; they always run from the threads build (a
# coarray program cannot start as a single image with Debian's OpenMPI).
check test:
ifeq ($(BACKEND),coarray)
	@$(MAKE) --no-print-directory BACKEND=threads check-unit
	@$(MAKE) --no-print-directory BACKEND=coarray check-coarray
else
	@$(MAKE) --no-print-directory BACKEND=threads check-unit check-threads
endif

check-unit: $(TEST_BIN) $(PROGRAM_BIN)
	./$(TEST_BIN) $(OBJDIR)
	./$(PROGRAM_BIN) --version

# Two OpenMP threads: the parallel loop, the counters and the exit status,
# without RAW files (the inputs do not exist, so all three must fail).
check-threads: $(PROGRAM_BIN)
	@echo "./$(PROGRAM_BIN) -j 2 missing1.CR2 missing2.CR2 missing3.CR2"
	@out=$$(./$(PROGRAM_BIN) -j 2 missing1.CR2 missing2.CR2 missing3.CR2 2>&1); rc=$$?; \
	echo "$$out" | sed 's/^/    | /'; \
	if echo "$$out" | grep -q 'Done: 0 converted, 3 failed' && [ $$rc -eq 1 ]; then \
	  echo "check-threads: OK (exit status $$rc as expected)"; \
	else \
	  echo "check-threads: FAILED (exit status $$rc)"; exit 1; \
	fi

# Two images, dynamic schedule (atomics), co_sum and the exit status.
check-coarray: $(PROGRAM_BIN)
	@echo "$(CAFRUN) -n 2 ./$(PROGRAM_BIN) --schedule=dynamic missing1.CR2 missing2.CR2 missing3.CR2"
	@out=$$($(CAFRUN) -n 2 ./$(PROGRAM_BIN) --schedule=dynamic \
	        missing1.CR2 missing2.CR2 missing3.CR2 2>&1); rc=$$?; \
	echo "$$out" | sed 's/^/    | /'; \
	if echo "$$out" | grep -q 'Done: 0 converted, 3 failed' && [ $$rc -ne 0 ]; then \
	  echo "check-coarray: 2-image run OK (exit status $$rc as expected)"; \
	else \
	  echo "check-coarray: FAILED (exit status $$rc)"; exit 1; \
	fi

# Portable packages (see packaging/release.mk and the README).
release: release-$(HOST_PLATFORM)

release-linux release-macos release-freebsd release-windows:
	@$(MAKE) --no-print-directory RELEASE=$(@:release-%=%) release-package

# ------------------------------------------------------------- compile rules
$(OBJDIR):
	mkdir -p $@

$(OBJDIR)/%.o: %.f90 | $(OBJDIR)
	$(FC_BUILD) $(ALL_FFLAGS) -J$(OBJDIR) -I$(OBJDIR) -c $< -o $@
$(OBJDIR)/%.o: %.F90 | $(OBJDIR)
	$(FC_BUILD) $(ALL_FFLAGS) -J$(OBJDIR) -I$(OBJDIR) -cpp $(CPPDEFS) -c $< -o $@

$(OBJDIR)/%.o: %.c | $(OBJDIR)
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJDIR)/r2f_libraw.o: r2f_libraw.c $(LIBRAW_DEP) | $(OBJDIR)
ifeq ($(LIBRAW_CHECK),yes)
	@$(PKG_CONFIG) --exists $(LIBRAW_PC) 2>/dev/null || test -f /usr/include/libraw/libraw.h || \
	  { echo "LibRaw development files not found - install them with:"; \
	    echo "  sudo apt install libraw-dev   (macOS: brew install libraw pkg-config," \
	         "FreeBSD: pkg install libraw pkgconf)"; exit 1; }
endif
	$(CC) $(CFLAGS) $(LIBRAW_CFLAGS) -c $< -o $@

# m_config.F90 takes the version from the VERSION file.
$(OBJDIR)/m_config.o: VERSION

# ------------------------------------------- module dependencies (use ...)
D := $(OBJDIR)
$(D)/m_strings.o:       $(D)/m_platform.o
$(D)/m_log.o:           $(D)/m_config.o
$(D)/m_pixel_ops.o:     $(D)/m_frame.o
$(D)/m_raw.o:           $(D)/m_libraw.o $(D)/m_strings.o $(D)/m_platform.o $(D)/m_frame.o
$(D)/m_metadata.o:      $(D)/m_frame.o $(D)/m_fits_header.o $(D)/m_time.o $(D)/m_strings.o \
                        $(D)/m_config.o
$(D)/m_fits_writer.o:   $(D)/m_frame.o $(D)/m_fits_header.o $(D)/m_metadata.o $(D)/m_bytes.o
$(D)/m_tiff_writer.o:   $(D)/m_frame.o $(D)/m_fits_header.o $(D)/m_metadata.o $(D)/m_bytes.o \
                        $(D)/m_time.o
$(D)/m_pgm_writer.o:    $(D)/m_frame.o $(D)/m_metadata.o $(D)/m_bytes.o $(D)/m_strings.o
$(D)/m_output.o:        $(D)/m_strings.o $(D)/m_options.o $(D)/m_frame.o $(D)/m_fits_writer.o \
                        $(D)/m_tiff_writer.o $(D)/m_pgm_writer.o $(D)/m_platform.o
$(D)/m_options.o:       $(D)/m_strings.o $(D)/m_frame.o $(D)/m_config.o
$(D)/m_jobs.o:          $(D)/m_strings.o $(D)/m_options.o $(D)/m_frame.o $(D)/m_raw.o \
                        $(D)/m_pixel_ops.o $(D)/m_output.o $(D)/m_platform.o $(D)/m_log.o
$(D)/m_workers_threads.o: $(D)/m_jobs.o $(D)/m_strings.o $(D)/m_log.o
$(D)/m_workers_coarray.o: $(D)/m_jobs.o $(D)/m_options.o $(D)/m_strings.o $(D)/m_log.o
$(D)/raw2fits.o:        $(D)/m_strings.o $(D)/m_options.o $(D)/m_output.o $(D)/m_platform.o \
                        $(D)/m_raw.o $(D)/m_jobs.o $(D)/m_workers_$(BACKEND).o $(D)/m_log.o \
                        $(D)/m_config.o
$(D)/test_raw2fits.o:   $(D)/m_strings.o $(D)/m_time.o $(D)/m_fits_header.o $(D)/m_frame.o \
                        $(D)/m_pixel_ops.o $(D)/m_options.o $(D)/m_output.o $(D)/m_platform.o

# ----------------------------------------------------------------- install
install: $(PROGRAM_BIN)
	install -d $(DESTDIR)$(BINDIR) $(DESTDIR)$(MANDIR)
	for b in raw2fits$(EXE) raw2fits-caf; do \
	  if [ -f "$$b" ]; then install -m 755 "$$b" $(DESTDIR)$(BINDIR)/; fi; \
	done
	install -m 755 scripts/raw2fits-par $(DESTDIR)$(BINDIR)/raw2fits-par
	install -m 644 man/raw2fits.1 $(DESTDIR)$(MANDIR)/raw2fits.1

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/raw2fits$(EXE) $(DESTDIR)$(BINDIR)/raw2fits-caf \
	      $(DESTDIR)$(BINDIR)/raw2fits-par $(DESTDIR)$(MANDIR)/raw2fits.1

clean:
	rm -rf build/release-* build/debug-* build/rel-* raw2fits raw2fits.exe raw2fits-caf

distclean: clean
	rm -rf build dist raw2fits-$(VERSION).tar.gz

dist:
	tar -czf raw2fits-$(VERSION).tar.gz --transform 's,^,raw2fits-$(VERSION)/,' \
	    Makefile VERSION README.md LICENSE-NOTICE.md src tests scripts man packaging

help:
	@sed -n '3,14p' Makefile | sed 's/^# \{0,1\}//'
	@echo
	@echo "Platform:     $(HOST_PLATFORM) ($(UNAME_S))"
	@echo "Backend:      BACKEND=$(BACKEND) -> $(PROGRAM_BIN)  (compiler $(FC_BUILD))"
	@echo "Version:      $(VERSION) (from the VERSION file)"
	@echo "Build type:   BUILD=$(BUILD)"
	@echo "LibRaw flags: $(if $(LIBRAW_CFLAGS),$(LIBRAW_CFLAGS),(none)) $(LIBRAW_LIBS)"
	@echo "Install to:   $(DESTDIR)$(BINDIR)"
