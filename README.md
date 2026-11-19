<p align="center"><img src="packaging/logo/raw2fits.svg" alt="raw2fits" width="128"></p>

# raw2fits

`raw2fits` converts camera RAW files (CR2, CR3, NEF, ARW, RAF, ORF, RW2, DNG, …) into **16-bit FITS** files for stacking. It is written in Fortran 2018 and converts several files at once, either on OpenMP threads or on coarray images. LibRaw decodes the files. The sensor data are written **unprocessed**: no demosaicing, white balance or colour conversion. The Bayer pattern and the exposure metadata go into the FITS header, so Siril, ASTAP and similar tools can calibrate and debayer the files themselves.

## Install on GNU/Linux (Debian / Ubuntu / Mint)

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

## License

**raw2fits** is available under LGPL-2.1.
