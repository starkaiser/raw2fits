#!/bin/sh
# package.sh PLATFORM BINARY VERSION ARCH OUTDIR
#
# Turn a release binary into the distributable for PLATFORM:
#   linux    OUTDIR/raw2fits-VERSION-ARCH.AppImage
#   macos    OUTDIR/raw2fits-VERSION-macos-ARCH.tar.gz
#   freebsd  OUTDIR/raw2fits-VERSION-freebsd-ARCH.tar.gz
#   windows  OUTDIR/raw2fits-VERSION-windows-ARCH.exe
# Called by `make release-*`; STRIP may name the strip program.
set -eu

plat=$1
bin=$2
ver=$3
arch=$4
out=$5
root=$(cd "$(dirname "$0")/.." && pwd)
strip_cmd=${STRIP:-strip}
work="$(dirname "$bin")/package"

rm -rf "$work"
mkdir -p "$work" "$out"

docs() {   # docs DIR: user documentation next to the program
  cp "$root/README.md" "$root/LICENSE-NOTICE.md" "$1/"
}

case $plat in
# ------------------------------------------------------------------- Linux
linux)
  app="$work/raw2fits.AppDir"
  mkdir -p "$app/usr/bin" "$app/usr/lib" "$app/usr/share/man/man1" \
           "$app/usr/share/applications" "$app/usr/share/icons/hicolor/256x256/apps" \
           "$app/usr/share/icons/hicolor/scalable/apps" "$app/usr/share/doc/raw2fits"
  cp "$bin" "$app/usr/bin/raw2fits"
  "$strip_cmd" "$app/usr/bin/raw2fits"
  sh "$root/packaging/bundle-libs.sh" "$app/usr/bin/raw2fits" "$app/usr/lib"
  cp "$root/man/raw2fits.1" "$app/usr/share/man/man1/"
  docs "$app/usr/share/doc/raw2fits"
  cp "$root/packaging/linux/raw2fits.desktop" "$app/raw2fits.desktop"
  cp "$root/packaging/linux/raw2fits.desktop" "$app/usr/share/applications/"
  cp "$root/packaging/logo/raw2fits-256.png" "$app/raw2fits.png"
  cp "$root/packaging/logo/raw2fits-256.png" "$app/usr/share/icons/hicolor/256x256/apps/raw2fits.png"
  cp "$root/packaging/logo/raw2fits.svg" "$app/usr/share/icons/hicolor/scalable/apps/raw2fits.svg"
  ln -s raw2fits.png "$app/.DirIcon"
  ln -s usr/bin/raw2fits "$app/AppRun"

  tool=${APPIMAGETOOL:-$(command -v appimagetool || true)}
  if [ -z "$tool" ]; then
    tool="$root/build/tools/appimagetool-$arch.AppImage"
    if [ ! -x "$tool" ]; then
      mkdir -p "$root/build/tools"
      u="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$arch.AppImage"
      echo "package: downloading $u"
      if command -v curl >/dev/null 2>&1; then curl -fL --retry 3 -o "$tool.part" "$u"
      else wget -O "$tool.part" "$u"; fi
      mv "$tool.part" "$tool"
      chmod +x "$tool"
    fi
  fi
  target="$out/raw2fits-$ver-$arch.AppImage"
  # appimagetool is itself an AppImage: extract-and-run avoids needing FUSE.
  APPIMAGE_EXTRACT_AND_RUN=1 ARCH=$arch "$tool" --no-appstream "$app" "$target"
  echo "package: $target"
  ;;

# ------------------------------------------------------------------- macOS
macos)
  name="raw2fits-$ver-macos-$arch"
  d="$work/$name"
  mkdir -p "$d"
  cp "$bin" "$d/raw2fits"
  "$strip_cmd" "$d/raw2fits"
  # Copy any remaining non-system dylibs (e.g. from Homebrew's gcc) into lib/.
  if otool -L "$d/raw2fits" | tail -n +2 | awk '{print $1}' | grep -Eqv '^(/usr/lib/|/System/)'; then
    command -v dylibbundler >/dev/null 2>&1 ||
      { echo "package: non-system dylibs found; install dylibbundler (brew install dylibbundler)" >&2; exit 1; }
    dylibbundler -od -b -x "$d/raw2fits" -d "$d/lib" -p @executable_path/lib/
  fi
  # Ad-hoc signatures (required on Apple Silicon after relinking).
  for f in "$d/raw2fits" "$d"/lib/*.dylib; do
    [ -f "$f" ] && codesign --force --sign - "$f"
  done
  cp "$root/man/raw2fits.1" "$d/"
  docs "$d"
  target="$out/$name.tar.gz"
  tar -C "$work" -czf "$target" "$name"
  echo "package: $target"
  ;;

# ----------------------------------------------------------------- FreeBSD
freebsd)
  name="raw2fits-$ver-freebsd-$arch"
  d="$work/$name"
  mkdir -p "$d/bin" "$d/lib" "$d/man/man1"
  cp "$bin" "$d/bin/raw2fits"
  "$strip_cmd" "$d/bin/raw2fits"
  sh "$root/packaging/bundle-libs.sh" "$d/bin/raw2fits" "$d/lib"
  rmdir "$d/lib" 2>/dev/null || true
  cp "$root/man/raw2fits.1" "$d/man/man1/"
  docs "$d"
  target="$out/$name.tar.gz"
  tar -C "$work" -czf "$target" "$name"
  echo "package: $target"
  ;;

# ----------------------------------------------------------------- Windows
windows)
  target="$out/raw2fits-$ver-windows-$arch.exe"
  cp "$bin" "$target"
  "$strip_cmd" "$target"
  echo "package: $target"
  ;;

*)
  echo "package: unknown platform '$plat'" >&2
  exit 2 ;;
esac
