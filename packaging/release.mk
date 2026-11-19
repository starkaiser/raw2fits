# packaging/release.mk - portable release builds, included by the Makefile
# when RELEASE=<linux|macos|freebsd|windows> (make release / release-*).
#
# Every release binary is the OpenMP build (-fcoarray=single -fopenmp: no
# MPI; parallel with `raw2fits -j N`), statically linked with the reentrant
# libraw_r from a minimal LibRaw built by packaging/build-libraw.sh (no
# OpenMP/JPEG/zlib/LCMS inside LibRaw), and with the GCC runtimes linked
# statically where the platform allows it (libgomp is bundled otherwise):
#
#   linux    dist/raw2fits-VERSION-ARCH.AppImage
#   macos    dist/raw2fits-VERSION-macos-ARCH.tar.gz   (raw2fits + lib/ if needed)
#   freebsd  dist/raw2fits-VERSION-freebsd-ARCH.tar.gz (bin/ lib/ man/)
#   windows  dist/raw2fits-VERSION-windows-ARCH.exe    (one self-contained file)

LIBRAW_VERSION ?= 0.22.3
ARCH ?= $(shell uname -m)
DISTDIR ?= dist

# Releases always use the OpenMP thread backend (no MPI on the target).
BACKEND := threads

ifeq ($(filter $(RELEASE),linux macos freebsd windows),)
  $(error RELEASE must be linux, macos, freebsd or windows (got '$(RELEASE)'))
endif
ifneq ($(RELEASE),windows)
  ifneq ($(RELEASE),$(HOST_PLATFORM))
    $(error release-$(RELEASE) must be built on $(RELEASE); this is $(HOST_PLATFORM). \
            Only release-windows can be cross-compiled (from Linux with MinGW-w64))
  endif
endif

# C++ compiler for LibRaw: the g++ that belongs to $(GFORTRAN), so that its
# libstdc++ matches the Fortran runtime (gfortran13 -> g++13 on FreeBSD).
LR_CC  := $(CC)
LR_CXX := $(subst gfortran,g++,$(GFORTRAN))
LR_HOST :=
LR_CPPFLAGS :=
RUN_TESTS := yes

# ---------------------------------------------------------------- per OS
ifeq ($(RELEASE),linux)
  # GCC runtimes static; anything else ldd still lists (e.g. libquadmath) is
  # copied into the AppImage's usr/lib and found through the rpath.
  LDFLAGS := -static-libgfortran -static-libgcc -Wl,--disable-new-dtags \
             -Wl,-rpath,'$$ORIGIN/../lib'
  CXXLIB  := -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic -lpthread
endif

ifeq ($(RELEASE),freebsd)
  LDFLAGS := -static-libgfortran -static-libgcc -Wl,--disable-new-dtags -Wl,-z,origin \
             -Wl,-rpath,'$$ORIGIN/../lib'
  CXXLIB  := -Wl,-Bstatic -lstdc++ -Wl,-Bdynamic -lpthread
endif

ifeq ($(RELEASE),macos)
  # LibRaw is built with the system clang++ (libc++ is part of macOS).
  LR_CXX  := c++
  LDFLAGS := -static-libgfortran -static-libgcc
  CXXLIB  := -lc++ -lpthread
  ARCH    := $(shell uname -m)
endif

ifeq ($(RELEASE),windows)
  ifeq ($(HOST_PLATFORM),windows)
    CROSS ?=
    RUN_TESTS := yes
  else
    CROSS ?= x86_64-w64-mingw32-
    RUN_TESTS := no
  endif
  GFORTRAN := $(CROSS)gfortran
  CC       := $(CROSS)gcc
  LR_CC    := $(CROSS)gcc
  LR_CXX   := $(CROSS)g++
  LR_HOST  := $(patsubst %-,%,$(CROSS))
  WINDRES  ?= $(CROSS)windres
  STRIP    := $(CROSS)strip
  EXE      := .exe
  ARCH     := $(if $(CROSS),$(firstword $(subst -, ,$(CROSS))),$(shell uname -m))
  CFLAGS   := -O2 -std=gnu11 -Wall -Wextra
  LDFLAGS  := -static -static-libgfortran -static-libgcc
  CXXLIB   := -lstdc++ -lws2_32 -lpthread
  LR_CPPFLAGS := -DLIBRAW_NODLL
  EXTRA_OBJS = $(OBJDIR)/raw2fits_res.o
endif

# ------------------------------------------------------------------ LibRaw
# (an alias: a recipe line naming $$(MAKE) would run even under make -n)
MAKE_PROG := $(MAKE)
LR_DIR    := build/libraw-$(LIBRAW_VERSION)-$(RELEASE)-$(ARCH)
LR_PREFIX := $(abspath $(LR_DIR))/prefix
# libraw_r (reentrant): files are decoded on several threads at once.
LR_LIB    := $(LR_PREFIX)/lib/libraw_r.a
LIBRAW_DEP    := $(LR_LIB)
LIBRAW_CFLAGS := -I$(LR_PREFIX)/include -I$(LR_PREFIX)/include/libraw $(LR_CPPFLAGS)
LIBRAW_LIBS   := $(LR_LIB) $(CXXLIB)
LIBRAW_CHECK  := no

OBJDIR      := build/rel-$(RELEASE)-$(ARCH)
PROGRAM_BIN := $(OBJDIR)/raw2fits$(EXE)
TEST_BIN    := $(OBJDIR)/test_raw2fits$(EXE)

.PHONY: release-package release-selftest

$(LR_LIB):
	CC="$(LR_CC)" CXX="$(LR_CXX)" CPPFLAGS="$(LR_CPPFLAGS)" MAKE="$(MAKE_PROG)" \
	  sh packaging/build-libraw.sh $(LIBRAW_VERSION) $(LR_DIR) $(LR_PREFIX) $(LR_HOST)

# Windows: icon, version information and a manifest (UTF-8 code page, long
# paths) compiled into the .exe.
$(OBJDIR)/raw2fits_res.o: packaging/windows/raw2fits.rc packaging/windows/raw2fits.exe.manifest \
                          packaging/logo/raw2fits.ico | $(OBJDIR)
	$(WINDRES) --include-dir=packaging/windows --include-dir=packaging/logo \
	  -O coff -i $< -o $@

release-selftest: $(TEST_BIN) $(PROGRAM_BIN)
	./$(TEST_BIN) $(OBJDIR)
	./$(PROGRAM_BIN) --version

release-package: $(PROGRAM_BIN) $(if $(filter yes,$(RUN_TESTS)),release-selftest)
	@mkdir -p $(DISTDIR)
	STRIP="$(STRIP)" sh packaging/package.sh $(RELEASE) $(PROGRAM_BIN) $(VERSION) $(ARCH) $(DISTDIR)
