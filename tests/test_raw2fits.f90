! raw2fits - camera RAW to FITS converter for astronomical stacking
!
! Copyright (c) 2026, Sorin Cătălin Păștiță
!
! Based on the LibRaw sample unprocessed_raw.cpp, Copyright (C) 2009-2024
! LibRaw LLC, with FITS and TIFF output by Han Kleijn.
!
! SPDX-License-Identifier: LGPL-2.1-only OR CDDL-1.0
!
! This file may be used under the terms of either the GNU Lesser General
! Public License version 2.1 or the Common Development and Distribution
! License version 1.0, at your option. See LICENSE-NOTICE.md and the license
! texts distributed with LibRaw.
!
! This software is distributed in the hope that it will be useful, but WITHOUT
! ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
! FOR A PARTICULAR PURPOSE.


! ==================================================================================================
!
! This file is part of raw2fits - convert camera RAW files to FITS for stacking
!
! PURPOSE :
!   Self-tests for raw2fits that need neither LibRaw nor RAW files.
!   Usage: test_raw2fits [scratch-directory]
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

program test_raw2fits

    use, intrinsic :: iso_fortran_env, only: int64, real64, output_unit, error_unit
    use :: m_strings
    use :: m_time, only: unix_to_iso8601, unix_to_julian_date
    use :: m_fits_header, only: fits_header_t, FITS_BLOCK, FITS_CARD
    use :: m_frame
    use :: m_pixel_ops, only: select_region, autoscale, apply_gamma
    use :: m_options, only: options_t, parse_args, FMT_FITS, FMT_TIFF, FMT_PGM, &
                            PARSE_OK, PARSE_HELP, PARSE_ERROR
    use :: m_output, only: output_stem, output_path, write_output
    use :: m_platform, only: path_exists, remove_file
    !$ use omp_lib, only: omp_get_max_threads

    implicit none (type, external)

    integer :: checks = 0, failures = 0
    character(len=:), allocatable :: scratch
    integer :: n

    call get_command_argument(1, length=n)
    if (n > 0) then
        allocate(character(len=n) :: scratch)
        call get_command_argument(1, scratch)
    else
        scratch = '.'
    end if

    call test_strings()
    call test_time()
    call test_cards()
    call test_options()
    call test_naming()
    call test_regions_and_cfa()
    call test_pixel_ops()
    call test_fits_file()
    call test_tiff_file()
    call test_pgm_file()
    call test_concurrent_writes()

    write(output_unit, '(a)') 'test_raw2fits: ' // str(checks - failures) // '/' // &
        str(checks) // ' checks passed'
    if (failures > 0) error stop 1

contains

    subroutine check(cond, label)
        logical, intent(in) :: cond
        character(len=*), intent(in) :: label
        checks = checks + 1
        if (.not. cond) then
            failures = failures + 1
            write(error_unit, '(a)') 'FAIL: ' // label
        end if
    end subroutine check

    !> Exact string equality (Fortran's == ignores trailing blanks).
    logical function same(a, b)
        character(len=*), intent(in) :: a, b
        same = len(a) == len(b)
        if (same) same = a == b
    end function same

    ! ------------------------------------------------------------------------
    subroutine test_strings()
        type(string_list_t) :: list
        call check(same(path_basename('/a/b/IMG_1.CR2'), 'IMG_1.CR2'), 'path_basename')
        call check(same(path_basename('IMG_1.CR2'), 'IMG_1.CR2'), 'path_basename without dir')
        call check(same(path_dirname('/a/b/IMG_1.CR2'), '/a/b'), 'path_dirname')
        call check(same(path_dirname('IMG_1.CR2'), ''), 'path_dirname without dir')
        call check(same(path_dirname('/IMG_1.CR2'), '/'), 'path_dirname root')
        call check(same(path_stem('IMG_1.CR2'), 'IMG_1'), 'path_stem')
        call check(same(path_stem('.hidden'), '.hidden'), 'path_stem dotfile')
        call check(same(path_stem('noext'), 'noext'), 'path_stem none')
        call check(same(path_join('out', 'a'), 'out/a'), 'path_join')
        call check(same(path_join('out/', 'a'), 'out/a'), 'path_join trailing slash')
        call check(same(path_join('', 'a'), 'a'), 'path_join empty dir')
        call check(same(str(42), '42'), 'str int')
        call check(same(str(-7_int64), '-7'), 'str int64')
        call check(same(str(30.0_real64), '30'), 'str real whole')
        call check(same(str(2.5_real64), '2.5'), 'str real fraction')
        call check(same(lower_ascii('FiTs'), 'fits'), 'lower_ascii')
        call check(same(strip('  a b ' // achar(13)), 'a b'), 'strip')
        call check(same(strip('   '), ''), 'strip blank')
        do n = 1, 40
            call list%push('item' // str(n))
        end do
        call check(list%n == 40, 'list grows')
        call check(same(list%get(33), 'item33'), 'list get after growth')
        call check(list%index_of('item7') == 7, 'list index_of')
        call check(list%index_of('item7 ') == 0, 'list index_of exact')
    end subroutine test_strings

    subroutine test_time()
        call check(same(unix_to_iso8601(0_int64, 0.0_real64), '1970-01-01T00:00:00.000'), 'epoch')
        call check(same(unix_to_iso8601(1700000000_int64, 0.0_real64), '2023-11-14T22:13:20.000'), &
                              'date 2023')
        call check(same(unix_to_iso8601(951782400_int64, 0.25_real64), '2000-02-29T00:00:00.250'), &
                              'leap day + subsec')
        call check(same(unix_to_iso8601(-86400_int64, 0.0_real64), '1969-12-31T00:00:00.000'), &
                              'before epoch')
        call check(same(unix_to_iso8601(1234567890_int64, 0.0_real64), '2009-02-13T23:31:30.000'), &
                              'date 2009')
        call check(abs(unix_to_julian_date(1700000000_int64, 0.0_real64) - 2460263.425925926_real64) &
                              < 1.0e-6_real64, 'julian date')
    end subroutine test_time

    subroutine test_cards()
        type(fits_header_t) :: h
        character(len=:), allocatable :: c, blk
        real(real64) :: r
        integer :: ios, k

        call h%add_logical('SIMPLE', .true., 'standard')
        c = h%card('SIMPLE')
        call check(c(1:10) == 'SIMPLE  = ' .and. c(30:30) == 'T', 'logical card')
        call h%add_int('NAXIS1', 6000, 'width')
        c = h%card('NAXIS1')
        call check(c(27:30) == '6000' .and. c(26:26) == ' ', 'integer right-justified to col 30')
        call check(c(31:33) == ' / ', 'comment separator')
        call h%add_string('BAYERPAT', 'RGGB', 'pattern')
        c = h%card('BAYERPAT')
        call check(c(11:20) == "'RGGB    '", 'string padded to 8 chars')
        call h%add_string('TELESCOP', "O'Brien 50mm")
        c = h%card('TELESCOP')
        call check(index(c, "'O''Brien 50mm'") == 11, 'quote doubled')
        call h%add_string('LONG', repeat('x', 100))
        c = h%card('LONG')
        call check(c(80:80) == "'", 'long string truncated inside the card')
        call h%add_real('EXPTIME', 30.0_real64, 'seconds')
        c = h%card('EXPTIME')
        read(c(11:30), *, iostat=ios) r
        call check(ios == 0 .and. abs(r - 30.0_real64) < 1.0e-9_real64, 'real card value')
        call h%add_real('JD', 2460263.42592593_real64, fmt='(f20.8)')
        c = h%card('JD')
        call check(same(trim(adjustl(c(11:30))), '2460263.42592593'), 'JD keeps 8 decimals')

        do k = 1, 40
            call h%add_comment('filler ' // str(k))
        end do
        call h%finish()
        blk = h%as_block()
        call check(mod(len(blk), FITS_BLOCK) == 0, 'header padded to 2880')
        call check(len(blk) == 2 * FITS_BLOCK, 'header spans two blocks')
        call check(blk((h%n - 1) * FITS_CARD + 1:(h%n - 1) * FITS_CARD + 3) == 'END', 'END card last')
    end subroutine test_cards

    subroutine test_options()
        type(string_list_t) :: args, args_help, args_fmt, inputs
        type(options_t) :: opts
        integer :: action
        character(len=:), allocatable :: msg

        call args%push('-qe')
        call args%push('--area=full')
        call args%push('-o')
        call args%push('out')
        call args%push('-ftiff')
        call args%push('--shot')
        call args%push('2')
        call args%push('a.CR2')
        call args%push('--')
        call args%push('-odd.NEF')
        call parse_args(args, opts, inputs, action, msg)
        call check(action == PARSE_OK, 'options parse ok: ' // msg)
        call check(opts%verbosity == 0, 'option -q (bundled)')
        call check(opts%keep_ext, 'option -e (bundled)')
        call check(opts%area == AREA_FULL, 'option --area=full')
        call check(same(trim(opts%outdir), 'out'), 'option -o DIR')
        call check(opts%format == FMT_TIFF, 'option -fVALUE')
        call check(opts%shot == 2, 'option --shot N')
        call check(inputs%n == 2, 'two inputs')
        call check(same(inputs%get(2), '-odd.NEF'), 'file after --')

        call expect_error([character(len=16) :: '--area=middle'], 'bad area rejected')
        call expect_error([character(len=16) :: '--shot'], 'missing value rejected')
        call expect_error([character(len=16) :: '-x'], 'unknown short option rejected')
        call expect_error([character(len=16) :: '--bogus'], 'unknown long option rejected')
        call expect_error([character(len=16) :: '--gamma=1'], 'value for flag rejected')
        call expect_error([character(len=16) :: '-s', 'minus1'], 'non-numeric shot rejected')
        call expect_error([character(len=16) :: '-q'], 'no input files rejected')

        call args_help%push('x.NEF')
        call args_help%push('-h')
        call parse_args(args_help, opts, inputs, action, msg)
        call check(action == PARSE_HELP, '-h gives help')

        call args_fmt%push('--format=PGM')
        call args_fmt%push('--ext=.fit')
        call args_fmt%push('x.NEF')
        call parse_args(args_fmt, opts, inputs, action, msg)
        call check(action == PARSE_OK .and. opts%format == FMT_PGM, 'format is case-insensitive')
        call check(same(trim(opts%ext), 'fit'), 'leading dot removed from --ext')
        call check(opts%format /= FMT_FITS, 'format changed')
    end subroutine test_options

    subroutine expect_error(list, label)
        character(len=*), intent(in) :: list(:)
        character(len=*), intent(in) :: label
        type(string_list_t) :: args, inputs
        type(options_t) :: opts
        integer :: action, k
        character(len=:), allocatable :: msg

        do k = 1, size(list)
            call args%push(trim(list(k)))
        end do
        call parse_args(args, opts, inputs, action, msg)
        call check(action == PARSE_ERROR .and. len(msg) > 0, label)
    end subroutine expect_error

    subroutine test_naming()
        type(string_list_t) :: args, inputs
        type(options_t) :: opts
        integer :: action
        character(len=:), allocatable :: msg

        call args%push('x.CR2')
        call parse_args(args, opts, inputs, action, msg)
        call check(same(output_stem('/data/IMG_1.CR2', opts), '/data/IMG_1'), 'stem next to input')
        call check(same(output_stem('IMG_1.CR2', opts), 'IMG_1'), 'stem in cwd')
        opts%keep_ext = .true.
        call check(same(output_stem('/data/IMG_1.CR2', opts), '/data/IMG_1.CR2'), 'stem --keep-ext')
        opts%outdir = 'fits'
        call check(same(output_stem('/data/IMG_1.CR2', opts), 'fits/IMG_1.CR2'), 'stem --outdir')
        opts%shot = 2
        call check(same(output_stem('/data/IMG_1.CR2', opts), 'fits/IMG_1.CR2-2'), 'stem --shot')
        call check(same(output_path('s', 1, 1, 'fits'), 's.fits'), 'single-channel path')
        call check(same(output_path('s', 2, 3, 'fits'), 's.ch2.fits'), 'multi-channel path')
    end subroutine test_naming

    ! ------------------------------------------------------------------------
    !> 7x5 sensor, 1-pixel margins (active 5x3), crop 4x4 at (2,1), RGGB at the
    !> active origin; pixel value 40000 + 100*y + x (1-based), > 32767 on purpose.
    subroutine make_frame(frame)
        type(frame_t), intent(out) :: frame
        integer :: x, y, r, c

        frame%raw_width = 7
        frame%raw_height = 5
        frame%channels = 1
        frame%left_margin = 1
        frame%top_margin = 1
        frame%active_width = 5
        frame%active_height = 3
        frame%has_crop = .true.
        frame%crop_left = 2
        frame%crop_top = 1
        frame%crop_width = 4
        frame%crop_height = 4
        frame%cfa = CFA_BAYER
        frame%cdesc = 'RGBG'
        do c = 0, 15
            do r = 0, 15
                if (mod(r, 2) == 0) then
                    frame%cfa_color(r, c) = merge(0, 1, mod(c, 2) == 0)
                else
                    frame%cfa_color(r, c) = merge(3, 2, mod(c, 2) == 0)
                end if
            end do
        end do
        frame%meta%exposure = 30.0_real64
        frame%meta%iso = 800.0_real64
        frame%meta%timestamp = 1700000000_int64
        frame%meta%has_sensor_temp = .true.
        frame%meta%sensor_temp = -10.5_real64
        frame%meta%make = 'Canon'
        frame%meta%model = 'EOS 6D'
        frame%meta%lens = ''
        allocate(frame%pixels(7, 5, 1))
        do y = 1, 5
            do x = 1, 7
                frame%pixels(x, y, 1) = u16_bits(40000 + 100 * y + x)
            end do
        end do
    end subroutine make_frame

    subroutine test_regions_and_cfa()
        type(frame_t) :: frame
        type(region_t) :: region
        logical :: fell_back, ok

        call make_frame(frame)
        call select_region(frame, AREA_ACTIVE, region, fell_back, ok)
        call check(ok .and. region%x0 == 1 .and. region%width == 5, 'active region')
        call check(same(cfa_pattern(frame, region, 2, 2), 'RGGB'), 'BAYERPAT active')
        call select_region(frame, AREA_FULL, region, fell_back, ok)
        call check(ok .and. region%width == 7 .and. region%height == 5, 'full region')
        call check(same(cfa_pattern(frame, region, 2, 2), 'BGGR'), 'BAYERPAT full (odd margins)')
        call select_region(frame, AREA_CROP, region, fell_back, ok)
        call check(ok .and. .not. fell_back .and. region%x0 == 2, 'crop region')
        call check(same(cfa_pattern(frame, region, 2, 2), 'GRBG'), 'BAYERPAT crop')
        frame%has_crop = .false.
        call select_region(frame, AREA_CROP, region, fell_back, ok)
        call check(ok .and. fell_back .and. same(trim(region%name), 'active'), 'crop falls back')
        frame%has_crop = .true.
        frame%crop_width = 99
        call select_region(frame, AREA_CROP, region, fell_back, ok)
        call check(ok .and. fell_back, 'out-of-range crop falls back')
    end subroutine test_regions_and_cfa

    subroutine test_pixel_ops()
        type(frame_t) :: frame
        integer :: factor, peak

        allocate(frame%pixels(2, 1, 1))
        frame%pixels(1, 1, 1) = u16_bits(1000)
        frame%pixels(2, 1, 1) = u16_bits(10)
        call autoscale(frame, factor, peak)
        call check(peak == 1000 .and. factor == 65, 'autoscale factor')
        call check(u16(frame%pixels(1, 1, 1)) == 65000, 'autoscale value')
        call check(frame%autoscale_factor == 65, 'autoscale recorded')
        call autoscale(frame, factor, peak)
        call check(factor == 1, 'autoscale skipped for high-range data')

        frame%pixels(1, 1, 1) = u16_bits(0)
        frame%pixels(2, 1, 1) = u16_bits(65535)
        call apply_gamma(frame)
        call check(u16(frame%pixels(1, 1, 1)) == 0 .and. u16(frame%pixels(2, 1, 1)) == 65535, &
                              'gamma end points')
        call check(u16(u16_bits(70000)) == 65535 .and. u16(u16_bits(-5)) == 0, 'u16 clamping')
    end subroutine test_pixel_ops

    ! ------------------------------------------------------------------------
    subroutine read_file(path, buf)
        character(len=*), intent(in) :: path
        character(len=:), allocatable, intent(out) :: buf
        integer :: unit, size_bytes

        open(newunit=unit, file=path, access='stream', form='unformatted', status='old', action='read')
        inquire(unit=unit, size=size_bytes)
        allocate(character(len=size_bytes) :: buf)
        read(unit) buf
        close(unit)
    end subroutine read_file

    integer function byte_at(buf, pos)
        character(len=*), intent(in) :: buf
        integer, intent(in) :: pos
        byte_at = iachar(buf(pos:pos))
    end function byte_at

    subroutine test_fits_file()
        type(frame_t) :: frame
        type(region_t) :: region
        character(len=:), allocatable :: path, buf, msg
        logical :: ok, fell_back
        integer :: k, data_off, v

        call make_frame(frame)
        call select_region(frame, AREA_FULL, region, fell_back, ok)
        path = path_join(scratch, 'r2f_test.fits')
        call write_output(frame, region, 1, FMT_FITS, path, ok, msg)
        call check(ok, 'FITS written: ' // msg)
        call check(.not. path_exists(path // '.part'), 'no .part file left behind')
        if (.not. ok) return
        call read_file(path, buf)

        call check(mod(len(buf), FITS_BLOCK) == 0, 'FITS size is a multiple of 2880')
        call check(buf(1:30) == 'SIMPLE  =                    T', 'FITS starts with SIMPLE')
        call check(index(buf(1:FITS_BLOCK), 'BZERO   =                32768') > 0, 'BZERO present')
        call check(index(buf(1:FITS_BLOCK), "BAYERPAT= 'BGGR    '") > 0, 'BAYERPAT in file')
        call check(index(buf(1:FITS_BLOCK), "DATE-OBS= '2023-11-14T22:13:20.000'") > 0, 'DATE-OBS')
        call check(index(buf(1:FITS_BLOCK), "ROWORDER= 'TOP-DOWN'") > 0, 'ROWORDER')

        data_off = -1
        do k = 1, len(buf) / FITS_CARD
            if (buf((k - 1) * FITS_CARD + 1:k * FITS_CARD) == 'END') then
                data_off = ((k * FITS_CARD + FITS_BLOCK - 1) / FITS_BLOCK) * FITS_BLOCK
                exit
            end if
        end do
        call check(data_off == FITS_BLOCK, 'data start after first header block')
        if (data_off < 0) return
        call check(len(buf) == data_off + FITS_BLOCK, 'data unit padded to one block')

        ! pixel (1,1) = 40101, stored big-endian as 40101 - 32768
        v = ieor(40101, 32768)
        call check(byte_at(buf, data_off + 1) == v / 256 .and. byte_at(buf, data_off + 2) == mod(v, 256), &
                              'first FITS pixel')
        ! pixel (1,2) starts the second row: 7 pixels later
        v = ieor(40201, 32768)
        call check(byte_at(buf, data_off + 15) == v / 256 .and. byte_at(buf, data_off + 16) == mod(v, 256), &
                              'second FITS row')
        call check(byte_at(buf, data_off + 2 * 35 + 1) == 0, 'zero padding after data')
        ok = remove_file(path)
    end subroutine test_fits_file

    subroutine test_tiff_file()
        type(frame_t) :: frame
        type(region_t) :: region
        character(len=:), allocatable :: path, buf, msg
        logical :: ok, fell_back
        integer :: v, n

        call make_frame(frame)
        call select_region(frame, AREA_ACTIVE, region, fell_back, ok)
        path = path_join(scratch, 'r2f_test.tiff')
        call write_output(frame, region, 1, FMT_TIFF, path, ok, msg)
        call check(ok, 'TIFF written: ' // msg)
        if (.not. ok) return
        call read_file(path, buf)
        n = len(buf)
        call check(buf(1:4) == 'II' // achar(42) // achar(0), 'TIFF magic')
        call check(index(buf, 'NAXIS1  =                    5') > 0, 'AstroTIFF description')
        call check(index(buf, 'BZERO') == 0, 'no BZERO in TIFF')
        ! last active pixel (x=6, y=4) = 40406, little-endian at the end of file
        v = 40406
        call check(byte_at(buf, n - 1) == mod(v, 256) .and. byte_at(buf, n) == v / 256, 'last TIFF pixel')
        ok = remove_file(path)
    end subroutine test_tiff_file

    subroutine test_pgm_file()
        type(frame_t) :: frame
        type(region_t) :: region
        character(len=:), allocatable :: path, buf, msg
        logical :: ok, fell_back
        integer :: v, start

        call make_frame(frame)
        call select_region(frame, AREA_CROP, region, fell_back, ok)
        path = path_join(scratch, 'r2f_test.pgm')
        call write_output(frame, region, 1, FMT_PGM, path, ok, msg)
        call check(ok, 'PGM written: ' // msg)
        if (.not. ok) return
        call read_file(path, buf)
        start = len(buf) - 2 * 4 * 4
        call check(buf(1:3) == 'P5' // achar(10), 'PGM magic')
        call check(buf(start - 9:start) == '4 4' // achar(10) // '65535' // achar(10), 'PGM size line')
        ! first crop pixel (x=3, y=2) = 40203, big-endian, no offset
        v = 40203
        call check(byte_at(buf, start + 1) == v / 256 .and. byte_at(buf, start + 2) == mod(v, 256), &
                              'first PGM pixel')
        ok = remove_file(path)
    end subroutine test_pgm_file

    !> Several FITS files written at the same time from OpenMP threads (a
    !> serial loop without OpenMP): checks that the writers, newunit= and the
    !> .part/rename step are thread-safe.
    subroutine test_concurrent_writes()
        integer, parameter :: NFILES = 16
        type(frame_t) :: frames(NFILES)
        type(region_t) :: region
        character(len=:), allocatable :: path, buf
        logical :: ok_all(NFILES), ok, fell_back
        integer :: k, x, y, v, data_off, nthreads

        nthreads = 1
        !$ nthreads = max(2, min(8, omp_get_max_threads()))
        do k = 1, NFILES
            call make_frame(frames(k))
            do y = 1, 5                       ! make every file's pixels distinct
                do x = 1, 7
                    frames(k)%pixels(x, y, 1) = u16_bits(1000 * k + 10 * y + x)
                end do
            end do
        end do
        call select_region(frames(1), AREA_FULL, region, fell_back, ok)

        !$omp parallel do num_threads(nthreads) schedule(dynamic, 1) private(k)
        do k = 1, NFILES
            call write_one(frames(k), region, k, ok_all(k))
        end do
        !$omp end parallel do

        call check(all(ok_all), 'concurrent writes succeeded (' // str(nthreads) // ' threads)')
        do k = 1, NFILES
            path = path_join(scratch, 'r2f_conc_' // str(k) // '.fits')
            if (.not. path_exists(path)) then
                call check(.false., 'concurrent file ' // str(k) // ' exists')
                cycle
            end if
            call read_file(path, buf)
            data_off = FITS_BLOCK
            v = ieor(1000 * k + 10 * 5 + 7, 32768)       ! last pixel (7,5)
            call check(len(buf) == 2 * FITS_BLOCK .and. &
                                  byte_at(buf, data_off + 69) == v / 256 .and. byte_at(buf, data_off + 70) == mod(v, 256), &
                                  'concurrent file ' // str(k) // ' content')
            call check(.not. path_exists(path // '.part'), 'concurrent file ' // str(k) // ' no .part')
            ok = remove_file(path)
        end do
    end subroutine test_concurrent_writes

    !> One file of test_concurrent_writes; its locals are private to the thread.
    subroutine write_one(frame, region, k, done)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: k
        logical, intent(out) :: done
        character(len=:), allocatable :: p, m

        p = path_join(scratch, 'r2f_conc_' // str(k) // '.fits')
        call write_output(frame, region, 1, FMT_FITS, p, done, m)
    end subroutine write_one

end program test_raw2fits
