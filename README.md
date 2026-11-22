<p align="center"><img src="packaging/logo/raw2fits.svg" alt="raw2fits" width="128"></p>

# raw2fits

A parallel program to convert RAW photos (CR2, CR3, NEF, ARW, RAF, ORF, RW2, DNG, …) into 16-bit FITS files, written in modern Fortran.

I am usually using Siril for astrophotography processing, but I wanted to try other programs. I found [ASTAP](https://www.hnsky.org/astap.htm),
which is very nice, but I saw that it takes a long time to convert the RAW photos before stacking, because it converts them one by one,
so I decided this is a good excuse for me to write a parallel program in Fortran. It is mostly an translation of LibRaw's `unprocessed_raw.cpp` sample (with FITS/TIFF additions by Han Kleijn)

## Download and run

See the [Releases](https://github.com/starkaiser/raw2fits/releases) page.

## Usage

```sh
raw2fits *.CR2                          # IMG_0001.CR2 -> IMG_0001.fits, next to the RAW
raw2fits -o fits/ ~/lights/*.NEF        # write into fits/ (created if needed)
raw2fits -n -o fits/ *.ARW              # dry run: show what would be done
raw2fits -j 4 -S -o fits/ *.ARW        # 4 threads; skip files already converted
raw2fits-par -o fits/ *.DNG             # coarray images if built, else threads
cafrun -n 4 raw2fits-caf -o fits/ *.NEF # coarray images directly (N >= 2)
```

`man raw2fits` has the full reference.

## Build from source

Two backends are available: threads and coarrays. Threas (OpenMP) are used for releases, coarrays (OpenCoarrays) are used only on GNU/Linux.

### GNU/Linux (Debian / Ubuntu / Mint):

**Install dependencies**
```
sudo apt install build-essential gfortran make pkg-config libraw-dev \
                 libcoarrays-openmpi-dev openmpi-bin   # provides caf / cafrun
```

**Build**
```
git clone https://github.com/starkaiser/raw2fits.git
cd raw2fits
make            # builds ./raw2fits (OpenMP threads) and ./raw2fits-caf (coarray images)
make check      # self-tests + a 2-thread run + a 2-image run (no RAW files needed)
sudo make install   # installs raw2fits, raw2fits-caf, raw2fits-par and the man page
```

### FreeBSD

**Install dependencies**
```
install gcc gmake
```

**Build**
```
git clone https://github.com/starkaiser/raw2fits.git
cd raw2fits
gmake
```

## Credits

Many thanks to the people behind [LibRaw](https://www.libraw.org/) and to Han Kleijn for writing [ASTAP](https://www.hnsky.org/astap.htm)!

## License

raw2fits is available under LGPL-2.1.
