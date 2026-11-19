#!/bin/sh
# build-libraw.sh VERSION WORKDIR PREFIX [HOST]
#
# Download LibRaw VERSION and install a minimal static libraw.a into PREFIX
# (falls back to cloning the GitHub tag).  OpenMP, JPEG, zlib and LCMS are
# disabled, so the release binaries need no further libraries.  None of them
# is used for reading unprocessed sensor data; only lossy (JPEG-compressed) and deflate-compressed DNGs need
# JPEG/zlib, and those are reported as unsupported by the release builds.
#
# HOST (e.g. x86_64-w64-mingw32) selects a cross build.  Uses $CC, $CXX,
# $CPPFLAGS and $MAKE from the environment.  Set LIBRAW_SHA256 to verify the
# download, or LIBRAW_URL to use another mirror.
set -eu

ver=$1
work=$2
prefix=$3
host=${4:-}
url=${LIBRAW_URL:-https://www.libraw.org/data/LibRaw-$ver.tar.gz}
make_cmd=${MAKE:-make}

mkdir -p "$work"
tarball="$work/LibRaw-$ver.tar.gz"

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 -o "$tarball.part" "$url"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$tarball.part" "$url"
  elif command -v fetch >/dev/null 2>&1; then          # FreeBSD base system
    fetch -o "$tarball.part" "$url"
  else
    echo "build-libraw: need curl, wget or fetch to download LibRaw" >&2
    return 1
  fi
}

from_git=no
if [ ! -s "$tarball" ]; then
  echo "build-libraw: downloading $url"
  if download; then
    mv "$tarball.part" "$tarball"
  elif command -v git >/dev/null 2>&1 && command -v autoreconf >/dev/null 2>&1; then
    # Fallback: the GitHub tag (needs autoconf, automake and libtool).
    echo "build-libraw: download failed, cloning tag $ver from GitHub instead"
    rm -f "$tarball.part"
    from_git=yes
  else
    rm -f "$tarball.part"
    echo "build-libraw: could not download $url" >&2
    exit 1
  fi
fi

if [ "$from_git" = no ] && [ -n "${LIBRAW_SHA256:-}" ]; then
  if command -v sha256sum >/dev/null 2>&1; then sum=$(sha256sum "$tarball" | cut -d' ' -f1)
  elif command -v shasum >/dev/null 2>&1; then sum=$(shasum -a 256 "$tarball" | cut -d' ' -f1)
  else sum=$(sha256 -q "$tarball"); fi
  if [ "$sum" != "$LIBRAW_SHA256" ]; then
    echo "build-libraw: SHA-256 mismatch for $tarball" >&2
    echo "  expected $LIBRAW_SHA256" >&2
    echo "  got      $sum" >&2
    exit 1
  fi
fi

rm -rf "$work/src"
mkdir -p "$work/src"
if [ "$from_git" = yes ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$ver" https://github.com/LibRaw/LibRaw "$work/src/LibRaw-$ver"
  (cd "$work/src/LibRaw-$ver" && autoreconf -fi >autoreconf.log 2>&1) ||
    { echo "build-libraw: autoreconf failed (install autoconf automake libtool)" >&2; exit 1; }
else
  tar -xzf "$tarball" -C "$work/src"
fi
src=$(find "$work/src" -mindepth 1 -maxdepth 1 -type d | head -n 1)
[ -x "$src/configure" ] || { echo "build-libraw: no configure script in $src" >&2; exit 1; }

jobs=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
set -- --prefix="$prefix" --disable-shared --enable-static \
       --disable-openmp --disable-jpeg --disable-zlib --disable-lcms --disable-examples
[ -n "$host" ] && set -- "$@" --host="$host"

echo "build-libraw: configuring LibRaw $ver ${host:+for $host }(CXX=${CXX:-c++})"
(
  cd "$src"
  ./configure "$@" CC="${CC:-cc}" CXX="${CXX:-c++}" \
    CPPFLAGS="${CPPFLAGS:-}" CFLAGS="-O2" CXXFLAGS="-O2" >configure.log 2>&1 ||
    { tail -n 30 configure.log >&2; echo "build-libraw: configure failed (see $src/configure.log)" >&2; exit 1; }
  # Remove make variables inherited from the calling make (jobserver etc.).
  env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL "$make_cmd" -j"$jobs" >build.log 2>&1 ||
    { tail -n 30 build.log >&2; echo "build-libraw: build failed (see $src/build.log)" >&2; exit 1; }
  env -u MAKEFLAGS -u MFLAGS -u MAKELEVEL "$make_cmd" install >install.log 2>&1 ||
    { tail -n 30 install.log >&2; echo "build-libraw: install failed" >&2; exit 1; }
)
for lib in libraw.a libraw_r.a; do
  [ -f "$prefix/lib/$lib" ] || { echo "build-libraw: $prefix/lib/$lib missing" >&2; exit 1; }
done
echo "build-libraw: installed libraw.a and libraw_r.a (reentrant) in $prefix/lib"
