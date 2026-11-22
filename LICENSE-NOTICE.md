# License and attribution notice

`raw2fits` is a Fortran 2018 reimplementation of the LibRaw sample `unprocessed_raw.cpp`. That sample is Copyright 2009-2024 LibRaw LLC and was modified for FITS/TIFF output by Han Kleijn. Its header states that it may be used under either the GNU LGPL version 2.1 or the CDDL version 1.0. Please consult the license files distributed with LibRaw for the complete terms, and use the license that applies to the copy of LibRaw/sample you are working from.

This package adapts the sample's behaviour in Fortran 2018. It includes small C helpers: `src/platform/r2f_libraw.c`, an accessor for fields of LibRaw's public `libraw_data_t` structure, and `src/platform/r2f_platform.c`, which provides POSIX file-system helpers. LibRaw itself is a separately linked dependency and keeps its own licensing terms. This notice is not a substitute for the full license texts.
