/*
 * GNU Lesser General Public License version 2.1
 *
 * Copyright (c) 2026, Sorin Cătălin Păștiță
 *
 * Based on the LibRaw sample unprocessed_raw.cpp, Copyright (C) 2009-2024
 * LibRaw LLC, with FITS and TIFF output by Han Kleijn.
 *
 * This file may be used under the terms of either the GNU Lesser General
 * Public License version 2.1 or the Common Development and Distribution
 * License version 1.0, at your option. See LICENSE-NOTICE.md and the license
 * texts distributed with LibRaw.
 *
 * This software is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE.
 */

/*
 * ==================================================================================================
 *
 * This file is part of raw2fits - Program to convert camera RAW files to FITS for stacking
 *
 * PURPOSE :
 *   The only operating-system specific code in raw2fits besides the LibRaw
 *   accessor. Every function has a plain C signature (char*, int) so the Fortran
 *   side (m_platform.f90) binds to it with BIND(C) and stays identical on
 *   GNU/Linux, FreeBSD, macOS and Windows: which OS this is, mkdir -p, a rename
 *   that replaces the target (Windows rename() refuses to), remove and stat.
 *   On Windows the C runtime is also told to expand wildcards (*.CR2).
 *   All functions take NUL-terminated strings and return 0 on success.
 *
 * WRITTEN BY :
 *   Sorin Cătălin Păștiță, November 2026
 *
 * ==================================================================================================
 */

#if !defined(_WIN32)
#  define _POSIX_C_SOURCE 200809L
#endif
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>

#if defined(_WIN32)
#  include <windows.h>
#  include <direct.h>
/* Let the MinGW-w64 C runtime expand wildcards (raw2fits *.CR2): unlike a
 * POSIX shell, cmd.exe and PowerShell pass the pattern through unchanged. */
int _dowildcard = -1;
#  define IS_SEP(c) ((c) == '/' || (c) == '\\')
static int make_one_dir(const char *p) { return _mkdir(p); }
#else
#  define IS_SEP(c) ((c) == '/')
static int make_one_dir(const char *p) { return mkdir(p, 0777); }
#endif

/* OS identifier for m_platform: 1 = POSIX (Linux, FreeBSD, ...), 2 = macOS, 3 = Windows. */
int r2f_platform(void)
{
#if defined(_WIN32)
    return 3;
#elif defined(__APPLE__)
    return 2;
#else
    return 1;
#endif
}

/* mkdir -p: create path and all missing parents.  Errors on intermediate
 * components (existing dirs, drive letters, UNC prefixes) are ignored; the
 * result is decided by whether path is a directory at the end. */
int r2f_mkdir_p(const char *path)
{
    if (!path || !*path) return -1;
    size_t n = strlen(path);
    char *buf = malloc(n + 1);
    if (!buf) return -1;
    memcpy(buf, path, n + 1);

    for (size_t i = 1; i <= n; ++i) {
        if (buf[i] == '\0' || IS_SEP(buf[i])) {
            char saved = buf[i];
            buf[i] = '\0';
            (void)make_one_dir(buf);
            buf[i] = saved;
        }
    }
    free(buf);

    struct stat st;
    return (stat(path, &st) == 0 && S_ISDIR(st.st_mode)) ? 0 : -1;
}

/* Rename, replacing an existing target (Windows rename() refuses to). */
int r2f_rename(const char *from, const char *to)
{
    if (!from || !to) return -1;
#if defined(_WIN32)
    return MoveFileExA(from, to, MOVEFILE_REPLACE_EXISTING | MOVEFILE_COPY_ALLOWED) ? 0 : -1;
#else
    return rename(from, to) == 0 ? 0 : -1;
#endif
}

int r2f_remove(const char *path)
{
    return (path && remove(path) == 0) ? 0 : -1;
}

/* 0 = does not exist, 1 = regular file, 2 = directory, 3 = something else. */
int r2f_path_kind(const char *path)
{
    struct stat st;
    if (!path || stat(path, &st) != 0) return 0;
    if (S_ISREG(st.st_mode)) return 1;
    if (S_ISDIR(st.st_mode)) return 2;
    return 3;
}
