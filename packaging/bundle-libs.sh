#!/bin/sh
# bundle-libs.sh BINARY LIBDIR
#
# Copy the shared libraries BINARY needs that are not part of the base
# system (as reported by ldd) into LIBDIR.  BINARY must be linked with an
# rpath of $ORIGIN/../lib (see packaging/release.mk).  Linux and FreeBSD.
set -eu

bin=$1
libdir=$2
mkdir -p "$libdir"

is_system() {
  case $(uname -s) in
    FreeBSD)
      case $1 in /lib/*|/usr/lib/*) return 0 ;; esac ;;
    *)  # glibc and the kernel's vDSO are always provided by the host
      case $(basename "$1") in
        ld-linux*|libc.so*|libm.so*|libmvec.so*|libpthread.so*|libdl.so*|librt.so*| \
        libresolv.so*|libutil.so*|linux-vdso*) return 0 ;;
      esac ;;
  esac
  return 1
}

ldd "$bin" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' | sort -u | while read -r lib; do
  is_system "$lib" && continue
  cp -L "$lib" "$libdir/"
  chmod 644 "$libdir/$(basename "$lib")"
  echo "bundle-libs: $(basename "$lib")"
done
