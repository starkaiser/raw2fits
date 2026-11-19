<p align="center"><img src="packaging/logo/raw2fits-wordmark.svg" alt="raw2fits" width="560"></p>

# raw2fits

`raw2fits` converts camera RAW files (CR2, CR3, NEF, ARW, RAF, ORF, RW2, DNG, …) into **16-bit FITS** files for stacking. It is written in Fortran 2018 and converts several files at once, either on OpenMP threads or on coarray images. LibRaw decodes the files. The sensor data are written **unprocessed**: no demosaicing, white balance or colour conversion. The Bayer pattern and the exposure metadata go into the FITS header, so Siril, ASTAP and similar tools can calibrate and debayer the files themselves.

It is a restructured version of `unprocessed_raw_f2018`, which in turn was a Fortran port of LibRaw's `unprocessed_raw.cpp` sample (with FITS/TIFF additions by Han Kleijn).

## Install on Linux Mint

```sh
sudo apt update
sudo apt install build-essential gfortran make pkg-config libraw-dev \
                 libcoarrays-openmpi-dev openmpi-bin   # provides caf / cafrun

make                    # ./raw2fits, OpenMP thread backend (the default)
make check              # self-tests + a 2-thread run (no RAW files needed)
make BACKEND=coarray    # ./raw2fits-caf, coarray backend (needs caf / cafrun)
make check BACKEND=coarray   # self-tests + a 2-image run
sudo make install       # installs the binaries built, raw2fits-par and the man page
```

The parallel backend is chosen when you build, with `BACKEND=threads|coarray`. The two backends are two implementations of the same module, `m_workers`, with identical public interfaces, so the rest of the program is the same:

- **`BACKEND=threads`** (default, and all release packages) compiles `src/convert/m_workers_threads.f90` into `./raw2fits`. It uses OpenMP threads (`-fopenmp`), needs no MPI, and converts several files at once with `-j N` (default: all cores). It links LibRaw's thread-safe `libraw_r`, which `libraw-dev` provides.
- **`BACKEND=coarray`** compiles `src/convert/m_workers_coarray.f90` into `./raw2fits-caf`. It uses coarray images through OpenCoarrays (`-fcoarray=lib`) and MPI.

The coarray build gets its own binary name and must be started with at least 2 images. With Debian/Ubuntu's OpenMPI 4.1, a coarray program aborts in `MPI_Win_create` ("invalid window") when it runs as a **single** image, whether started as `./prog` or `cafrun -n 1`. With one process, Open MPI picks its pt2pt one-sided component, which does not support `MPI_THREAD_MULTIPLE`. Two or more images work.

The version comes from the `VERSION` file. `make help` shows the current configuration.

## Usage

```sh
raw2fits *.CR2                          # IMG_0001.CR2 -> IMG_0001.fits, next to the RAW
raw2fits -o fits/ ~/lights/*.NEF        # write into fits/ (created if needed)
raw2fits -n -o fits/ *.ARW              # dry run: show what would be done
raw2fits -j 4 -S -o fits/ *.ARW        # 4 threads; skip files already converted
raw2fits-par -o fits/ *.DNG             # coarray images if built, else threads
cafrun -n 4 raw2fits-caf -o fits/ *.NEF # coarray images directly (N >= 2)
```

| Option | Meaning |
|---|---|
| `-f, --format=FMT` | `fits` (default), `tiff` (AstroTIFF), `pgm` |
| `-a, --area=AREA` | `active` visible area (default) · `full` whole sensor incl. masked pixels · `crop` camera default crop (falls back to active) |
| `-o, --outdir=DIR` | output directory (default: next to each RAW file) |
| `-e, --keep-ext` | keep the RAW extension: `IMG_0001.CR2.fits` |
| `--ext=EXT` | output extension, e.g. `--ext=fit` |
| `-S, --skip-existing` | skip files whose output exists (resume a run) |
| `-n, --dry-run` | list the plan, write nothing |
| `-s, --shot=N` | Nth image of multi-shot RAW files (default 0) |
| `-l, --list=FILE` | read file names from FILE (one per line, `#` comments) |
| `-A, --autoscale` | multiply low-range data by an integer factor |
| `-g, --gamma` | gamma 2.2, for viewing only (not linear any more) |
| `-j, --jobs=N` | OpenMP threads (default 0 = all cores, or `$OMP_NUM_THREADS`) |
| `--schedule=MODE` | coarray build: `static` (default) or `dynamic` sharing of files between images |
| `-q, --quiet` / `-v, --verbose` | errors only / per-file details |
| `-h, --help` / `-V, --version` | help / program, LibRaw and parallel backend info |

The options follow GNU style: short options can be combined (`-qS`), values can be attached (`-ofits`) or separate (`-o fits`), long options take `--name=value` or `--name value`, and `--` ends the options. For thousands of files, use `--list` instead of a huge command line.

The exit status is 0 on success, 1 if any file failed or was unsupported, and 2 for usage errors. `man raw2fits` has the full reference.

### Parallel runs

**OpenMP threads** (`raw2fits`, and every release package):

- **How it works:** `raw2fits -j N` converts N files at a time. Each thread takes the next unconverted file, so a slow file never holds up the others. Each thread has its own LibRaw handle, and messages are prefixed with `[thread/N]`.
- **Default thread count:** `-j 0`, the default, uses all cores, or `$OMP_NUM_THREADS` if that is set. The program never starts more threads than there are files.
- **Memory:** each thread holds one decoded frame in memory at a time. For a 24-megapixel sensor that is about 50 MB, plus LibRaw's buffers.
- **Disk speed:** with fast disks, conversion scales almost linearly with the number of threads. With slow disks (USB drives, network shares), the disk becomes the limit, and a lower `-j` can be just as fast.

**Coarray images** (`raw2fits-caf`): every image parses the same command line and builds the same file plan. The files are then shared between the images:

- **`--schedule=static`** (default): image *k* takes files *k*, *k+N*, …
- **`--schedule=dynamic`**: each image takes the next free file from an atomic counter.

Each image has its own LibRaw context. Messages are prefixed with `[image/N]`.

If any file fails, the run exits with status 1. Open MPI then adds a "process returned a non-zero exit code" notice; the `raw2fits:` error lines above it name the files that failed.

`raw2fits-par [-j N]` is a small wrapper around `cafrun -n N raw2fits-caf`. It defaults to the number of physical cores, because OpenMPI refuses more ranks than cores unless you pass `--oversubscribe`. You can set `RAW2FITS_JOBS` to change the default. With `-j 1`, or if `raw2fits-caf` or `cafrun` are missing, it runs `raw2fits -j N`, the OpenMP build, instead.

## Release builds (AppImage, macOS, FreeBSD, Windows)

`make release` builds a portable package for the system it runs on and writes it to `dist/`. `make release-windows` builds a single Windows `.exe`. It can be cross-compiled on Linux or built natively under MSYS2.

| Command | Run on | Result in `dist/` |
|---|---|---|
| `make release` | Linux | `raw2fits-1.0.0-x86_64.AppImage` |
| `make release` | macOS | `raw2fits-1.0.0-macos-arm64.tar.gz` (or `-x86_64`) |
| `gmake release` | FreeBSD | `raw2fits-1.0.0-freebsd-amd64.tar.gz` |
| `make release-windows` | Linux (MinGW-w64) or MSYS2 UCRT64 | `raw2fits-1.0.0-windows-x86_64.exe` |

What a release binary contains:

- **OpenMP threads.** Release binaries use the OpenMP backend (`-fopenmp`, `-fcoarray=single`). They need no MPI and run in parallel with `raw2fits -j N`, using all cores by default. The OpenMP runtime is linked statically into the Windows `.exe`; in the other packages `libgomp` is bundled where needed.
- **Its own copy of LibRaw.** `packaging/build-libraw.sh` downloads LibRaw 0.22.3 and builds minimal static libraries into `build/libraw-*`. The release links `libraw_r.a`, LibRaw's reentrant build, because files are decoded on several threads at once. If the libraw.org download fails, the script clones the GitHub tag instead, which needs autoconf, automake and libtool. Pick another LibRaw version with `make release LIBRAW_VERSION=x.y.z`.
- **Minimal LibRaw features.** OpenMP, JPEG, zlib and LCMS are switched off. None of them is needed for unprocessed sensor data. The exception is lossy (JPEG-compressed) and deflate-compressed DNGs, which the release builds report as unsupported. The source build with the system LibRaw reads them.
- **Self-tests.** Native release builds run the self-tests on the release binary before packaging it.

### Linux AppImage

```sh
sudo apt install build-essential gfortran curl    # + autoconf automake libtool for the git fallback
make release
./dist/raw2fits-1.0.0-x86_64.AppImage -j 8 -o fits/ *.CR2
```

- **Download:** the first run downloads `appimagetool` into `build/tools/`. To use a copy you already have, set `APPIMAGETOOL=/path/to/appimagetool`.
- **Linking:** the GCC runtimes are linked statically. Anything else `ldd` still lists is copied into the AppImage.
- **Compatibility:** the AppImage runs on distributions with the same or a newer glibc than the build machine. For the widest compatibility, build on the oldest release you want to support, for example Ubuntu 22.04.

### macOS

```sh
xcode-select --install
brew install gcc dylibbundler
make release
```

- **Contents:** the tarball holds `raw2fits`, the man page and the docs, plus a `lib/` folder if Homebrew's GCC runtime libraries could not be linked statically. They are bundled with `dylibbundler`, and the files are ad-hoc signed.
- **First run:** browsers mark downloaded files as quarantined. Clear the flag with `xattr -d com.apple.quarantine raw2fits`.
- **Architectures:** the build targets the machine's own architecture (arm64 or x86_64).

### FreeBSD

```sh
pkg install gcc gmake
gmake release
```

- **Compiler:** the Makefile finds versioned compilers such as `gfortran13` and builds LibRaw with the matching `g++13`.
- **Contents:** the tarball has `bin/raw2fits`, a `lib/` folder with any non-base libraries (found through `$ORIGIN`), the man page and the docs.

### Windows (single .exe)

The result is one self-contained `raw2fits.exe`. It has the icon and version information built in, plus a manifest that turns on UTF-8 file names (Windows 10 1903 and later) and long paths. Wildcards such as `*.CR2` are expanded by the program itself, because `cmd.exe` and PowerShell don't expand them. Both `\` and `/` work as path separators.

There are two ways to build it:

- **Cross-compile from Linux Mint:**
  ```sh
  sudo apt install gfortran-mingw-w64-x86-64 g++-mingw-w64-x86-64 curl
  make release-windows
  ```
  A cross build can't run the self-tests. Test the `.exe` on Windows, or under Wine.
- **Build natively on Windows** in an MSYS2 UCRT64 shell:
  ```sh
  pacman -S make curl mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-gcc-fortran
  make release-windows
  ```

Usage on Windows:

```bat
raw2fits-1.0.0-windows-x86_64.exe -j 8 -o fits *.CR2
```

The source build itself also works on macOS (`brew install gcc libraw pkg-config`, then `make`) and on FreeBSD (`pkg install gcc gmake libraw pkgconf`, then `gmake`).

## Output

- **Names:** `IMG_0001.CR2` → `IMG_0001.fits`. With `--shot N` (N > 0) the name gets a `-N` suffix. RAW files that store several channels (some DNG, Foveon) give one file per channel: `IMG_0001.ch1.fits`, `IMG_0001.ch2.fits`, … If two inputs would produce the same name (`a/IMG_1.CR2` and `a/IMG_1.DNG` into one directory), the run stops before converting and suggests `--keep-ext`.
- **Safe writes:** each file is written as `NAME.fits.part` and renamed when complete. An interrupted run never leaves truncated files, so `-S` can resume it safely.
- **FITS header:** `BITPIX=16`, `BZERO=32768` (standard unsigned 16-bit), `EXPTIME`, `DATE-OBS`, `JD`, `CCD-TEMP`, `ISOSPEED`, `GAIN` (= ISO, as before), `PEDESTAL*` (black level), `DATAMAX*`, `APERTURE`, `FOCALLEN`, `CAMMAKER`, `INSTRUME`, `TELESCOP` (lens), `BAYERPAT`, `FILT-PAT`, `XBAYROFF/YBAYROFF`, `ROWORDER='TOP-DOWN'`, `IMG_FLIP`, `RAWAREA/RAWX0/RAWY0` and `SWCREATE`. X-Trans files are marked with a comment instead of a 2×2 `BAYERPAT`. If you used `-A` or `-g`, a `HISTORY` card records it.
- **TIFF / PGM:** the same pixels. TIFF is little-endian, uncompressed, with the FITS cards in `ImageDescription` (AstroTIFF). PGM is a `P5` file with `# KEY=value` comments.
- **Floating-point DNG** data are scaled linearly so that the brightest finite sample becomes 65535.

The writers depend only on `frame_t`, not on LibRaw. That is why `make check` can test the FITS, TIFF and PGM output byte by byte without any RAW file.

## License

See `LICENSE-NOTICE.md`. The original sample is © 2009-2024 LibRaw LLC, with FITS/TIFF modifications by Han Kleijn. It is available under LGPL-2.1 or CDDL-1.0. LibRaw is a separately linked dependency under its own license.
