! GNU Lesser General Public License version 2.1
!
! Copyright (c) 2026, Sorin Cătălin Păștiță
!
! Based on the LibRaw sample unprocessed_raw.cpp, Copyright (C) 2009-2024
! LibRaw LLC, with FITS and TIFF output by Han Kleijn.
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
! This file is part of raw2fits - Program to convert camera RAW files to FITS for stacking
!
! PURPOSE :
!   Command-line interface: option definitions, parsing and help text.
!
!   Parsing follows GNU conventions: short options may be bundled (-qe) and
!   take their value attached or as the next argument (-ofits, -o fits);
!   long options take --name=value or --name value; '--' ends the options.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_options

    use, intrinsic :: iso_fortran_env, only: output_unit
    use :: m_strings, only: string_list_t, lower_ascii, strip
    use :: m_frame, only: AREA_FULL, AREA_ACTIVE, AREA_CROP
    use :: m_config, only: APP_NAME

    implicit none (type, external)

    private

    public :: options_t, parse_command_line, parse_args, print_usage

    integer, parameter, public :: FMT_FITS = 1, FMT_TIFF = 2, FMT_PGM = 3
    integer, parameter, public :: SCHED_STATIC = 1, SCHED_DYNAMIC = 2
    integer, parameter, public :: PARSE_OK = 0, PARSE_HELP = 1, PARSE_VERSION = 2, PARSE_ERROR = 3
    integer, parameter, public :: PATH_LEN = 4096

    type :: options_t
        integer :: format = FMT_FITS
        integer :: area = AREA_ACTIVE
        integer :: shot = 0
        integer :: verbosity = 1          !< 0 quiet, 1 normal, 2 verbose
        integer :: schedule = SCHED_STATIC
        integer :: jobs = 0               !< OpenMP threads, 0 = all cores
        logical :: autoscale = .false.
        logical :: gamma = .false.
        logical :: keep_ext = .false.
        logical :: skip_existing = .false.
        logical :: dry_run = .false.
        ! Fixed-length (not deferred-length) on purpose: see m_strings.
        character(len=PATH_LEN) :: outdir = ''    !< '' = next to the input file
        character(len=32) :: ext = ''             !< '' = default for the format
    end type options_t

contains

    !> Parse the program's own command line.
    subroutine parse_command_line(opts, inputs, action, msg)
        type(options_t), intent(out) :: opts
        type(string_list_t), intent(out) :: inputs
        integer, intent(out) :: action
        character(len=:), allocatable, intent(out) :: msg
        type(string_list_t) :: args
        character(len=:), allocatable :: arg
        integer :: i, n

        do i = 1, command_argument_count()
            call get_command_argument(i, length=n)
            allocate(character(len=n) :: arg)
            if (n > 0) call get_command_argument(i, arg)
            call args%push(arg)
            deallocate(arg)
        end do
        call parse_args(args, opts, inputs, action, msg)
    end subroutine parse_command_line

    !> Parse an argument list (separate from the command line for testing).
    subroutine parse_args(args, opts, inputs, action, msg)
        type(string_list_t), intent(in) :: args
        type(options_t), intent(out) :: opts
        type(string_list_t), intent(out) :: inputs
        integer, intent(out) :: action
        character(len=:), allocatable, intent(out) :: msg
        character(len=:), allocatable :: arg, key, val
        integer :: i, k, eq
        logical :: only_files, has_val

        msg = ''
        action = PARSE_OK
        only_files = .false.

        i = 0
        do while (i < args%n)
            i = i + 1
            arg = args%get(i)

            if (only_files .or. .not. is_option(arg)) then
                if (len(arg) > 0) call inputs%push(arg)
                cycle
            end if
            if (arg == '--') then
                only_files = .true.
                cycle
            end if

            if (arg(2:2) == '-') then
                ! ---- long option: --name, --name=value, --name value
                eq = index(arg, '=')
                has_val = eq > 0
                if (has_val) then
                    key = arg(3:eq - 1)
                    val = arg(eq + 1:)
                else
                    key = arg(3:)
                    val = ''
                end if
                key = long_name(key)
                if (len(key) == 0) then
                    if (has_val) arg = arg(1:eq - 1)
                    call fail("unknown option '" // arg // "'")
                    return
                end if
                if (takes_value(key)) then
                    if (.not. has_val) then
                        if (i >= args%n) then
                            call fail('option --' // key // ' requires a value')
                            return
                        end if
                        i = i + 1
                        val = args%get(i)
                    end if
                else if (has_val) then
                    call fail('option --' // key // ' does not take a value')
                    return
                end if
                call apply_option(key, val)
                if (action /= PARSE_OK) return
            else
                ! ---- one or more bundled short options: -qe, -ofits, -o fits
                k = 2
                do while (k <= len(arg))
                    key = short_name(arg(k:k))
                    if (len(key) == 0) then
                        call fail("unknown option '-" // arg(k:k) // "'")
                        return
                    end if
                    if (takes_value(key)) then
                        if (k < len(arg)) then
                            val = arg(k + 1:)
                        else if (i < args%n) then
                            i = i + 1
                            val = args%get(i)
                        else
                            call fail('option -' // arg(k:k) // ' requires a value')
                            return
                        end if
                        call apply_option(key, val)
                        exit
                    end if
                    call apply_option(key, '')
                    if (action /= PARSE_OK) return
                    k = k + 1
                end do
                if (action /= PARSE_OK) return
            end if
        end do

        if (inputs%n == 0) call fail('no input files')

    contains

        subroutine fail(text)
            character(len=*), intent(in) :: text
            action = PARSE_ERROR
            msg = text
        end subroutine fail

        subroutine apply_option(name, value)
            character(len=*), intent(in) :: name, value
            character(len=:), allocatable :: lower, err
            integer :: ios, n
            logical :: ok

            lower = lower_ascii(value)
            select case (name)
            case ('help')
                action = PARSE_HELP
            case ('version')
                action = PARSE_VERSION
            case ('format')
                select case (lower)
                case ('fits', 'fit', 'fts')
                    opts%format = FMT_FITS
                case ('tiff', 'tif')
                    opts%format = FMT_TIFF
                case ('pgm')
                    opts%format = FMT_PGM
                case default
                    call fail("invalid format '" // value // "' (expected fits, tiff or pgm)")
                end select
            case ('area')
                select case (lower)
                case ('full', 'sensor')
                    opts%area = AREA_FULL
                case ('active')
                    opts%area = AREA_ACTIVE
                case ('crop')
                    opts%area = AREA_CROP
                case default
                    call fail("invalid area '" // value // "' (expected active, full or crop)")
                end select
            case ('outdir')
                if (len(value) == 0) then
                    call fail('empty output directory')
                else if (len(value) > PATH_LEN) then
                    call fail('output directory name too long')
                else
                    opts%outdir = value
                end if
            case ('ext')
                n = verify(value, '.')            ! skip leading dots
                if (n == 0 .or. index(value, '/') > 0 .or. len(value) > len(opts%ext)) then
                    call fail("invalid extension '" // value // "'")
                else
                    opts%ext = value(n:)
                end if
            case ('shot')
                read(value, *, iostat=ios) n
                if (ios /= 0) then
                    call fail("invalid shot number '" // value // "'")
                else if (n < 0) then
                    call fail("invalid shot number '" // value // "'")
                else
                    opts%shot = n
                end if
            case ('jobs')
                read(value, *, iostat=ios) n
                if (ios /= 0) then
                    call fail("invalid number of jobs '" // value // "'")
                else if (n < 0) then
                    call fail("invalid number of jobs '" // value // "'")
                else
                    opts%jobs = n
                end if
            case ('list')
                call read_list_file(value, inputs, ok, err)
                if (.not. ok) call fail(err)
            case ('schedule')
                select case (lower)
                case ('static')
                    opts%schedule = SCHED_STATIC
                case ('dynamic')
                    opts%schedule = SCHED_DYNAMIC
                case default
                    call fail("invalid schedule '" // value // "' (expected static or dynamic)")
                end select
            case ('keep-ext')
                opts%keep_ext = .true.
            case ('skip-existing')
                opts%skip_existing = .true.
            case ('dry-run')
                opts%dry_run = .true.
            case ('autoscale')
                opts%autoscale = .true.
            case ('gamma')
                opts%gamma = .true.
            case ('quiet')
                opts%verbosity = 0
            case ('verbose')
                opts%verbosity = 2
            end select
        end subroutine apply_option

    end subroutine parse_args

    pure logical function is_option(arg)
        character(len=*), intent(in) :: arg
        is_option = .false.
        if (len(arg) >= 2) is_option = arg(1:1) == '-'
    end function is_option

    !> Canonical long option name ('' if unknown).
    pure function long_name(key) result(name)
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: name

        select case (key)
        case ('help', 'version', 'format', 'area', 'outdir', 'ext', 'shot', 'list', 'schedule', 'jobs', &
                    'keep-ext', 'skip-existing', 'dry-run', 'autoscale', 'gamma', 'quiet', 'verbose')
            name = key
        case ('output-dir')
            name = 'outdir'
        case default
            name = ''
        end select
    end function long_name

    pure function short_name(c) result(name)
        character(len=1), intent(in) :: c
        character(len=:), allocatable :: name

        select case (c)
        case ('h')
            name = 'help'
        case ('V')
            name = 'version'
        case ('f')
            name = 'format'
        case ('a')
            name = 'area'
        case ('o')
            name = 'outdir'
        case ('s')
            name = 'shot'
        case ('l')
            name = 'list'
        case ('e')
            name = 'keep-ext'
        case ('S')
            name = 'skip-existing'
        case ('n')
            name = 'dry-run'
        case ('A')
            name = 'autoscale'
        case ('g')
            name = 'gamma'
        case ('q')
            name = 'quiet'
        case ('v')
            name = 'verbose'
        case ('j')
            name = 'jobs'
        case default
            name = ''
        end select
    end function short_name

    pure logical function takes_value(name)
        character(len=*), intent(in) :: name
        select case (name)
        case ('format', 'area', 'outdir', 'ext', 'shot', 'list', 'schedule', 'jobs')
            takes_value = .true.
        case default
            takes_value = .false.
        end select
    end function takes_value

    !> Append the file names listed in path (one per line, '#' = comment).
    subroutine read_list_file(path, inputs, ok, msg)
        character(len=*), intent(in) :: path
        type(string_list_t), intent(inout) :: inputs
        logical, intent(out) :: ok
        character(len=:), allocatable, intent(out) :: msg
        character(len=:), allocatable :: line
        character(len=256) :: iomsg
        integer :: unit, ios

        ok = .false.
        msg = ''
        open(newunit=unit, file=path, status='old', action='read', form='formatted', &
                  access='sequential', iostat=ios, iomsg=iomsg)
        if (ios /= 0) then
            msg = "cannot open list file '" // path // "': " // trim(iomsg)
            return
        end if
        do
            call read_line(unit, line, ios)
            if (is_iostat_end(ios)) exit
            if (ios /= 0) then
                msg = "error reading list file '" // path // "'"
                close(unit)
                return
            end if
            line = strip(line)
            if (len(line) == 0) cycle
            if (line(1:1) == '#') cycle
            call inputs%push(line)
        end do
        close(unit)
        ok = .true.
    end subroutine read_list_file

    !> Read one line of any length.
    subroutine read_line(unit, line, ios)
        integer, intent(in) :: unit
        character(len=:), allocatable, intent(out) :: line
        integer, intent(out) :: ios
        character(len=1024) :: buffer
        integer :: nread

        line = ''
        do
            read(unit, '(a)', advance='no', iostat=ios, size=nread) buffer
            line = line // buffer(1:nread)
            if (is_iostat_eor(ios)) then
                ios = 0
                return
            end if
            if (is_iostat_end(ios) .and. len(line) > 0) then
                ios = 0                      ! last line without a newline
                return
            end if
            if (ios /= 0) return
        end do
    end subroutine read_line

    subroutine print_usage()
        character(len=*), parameter :: p = APP_NAME
        integer :: u
        u = output_unit

        write(u, '(a)') 'Usage: ' // p // ' [OPTION]... RAW-FILE...'
        write(u, '(a)') '       ' // p // '-par [-j N] [OPTION]... RAW-FILE...   (N parallel images)'
        write(u, '(a)') ''
        write(u, '(a)') 'Convert camera RAW files to 16-bit FITS for stacking. The sensor data are'
        write(u, '(a)') 'written unprocessed (no demosaicing, white balance or colour conversion);'
        write(u, '(a)') 'the CFA/Bayer pattern and exposure metadata are stored in the header.'
        write(u, '(a)') ''
        write(u, '(a)') 'Output:'
        write(u, '(a)') '  -f, --format=FMT       fits (default), tiff (AstroTIFF) or pgm'
        write(u, '(a)') '  -a, --area=AREA        active  visible sensor area (default)'
        write(u, '(a)') '                         full    whole sensor incl. masked (black) pixels'
        write(u, '(a)') '                         crop    camera default crop (else active area)'
        write(u, '(a)') '  -o, --outdir=DIR       write files to DIR, created if needed'
        write(u, '(a)') '                         (default: next to each RAW file)'
        write(u, '(a)') '  -e, --keep-ext         keep the RAW extension: IMG_0001.CR2.fits'
        write(u, '(a)') '      --ext=EXT          output file extension (default: fits/tiff/pgm)'
        write(u, '(a)') '  -S, --skip-existing    skip files whose output already exists'
        write(u, '(a)') '  -n, --dry-run          show what would be converted, write nothing'
        write(u, '(a)') ''
        write(u, '(a)') 'Input:'
        write(u, '(a)') '  -s, --shot=N           Nth image of multi-shot RAW files (default 0)'
        write(u, '(a)') '  -l, --list=FILE        read RAW file names from FILE, one per line'
        write(u, '(a)') ''
        write(u, '(a)') 'Pixel processing (changes the data - not for stacking):'
        write(u, '(a)') '  -A, --autoscale        multiply low-range data by an integer factor'
        write(u, '(a)') '  -g, --gamma            apply gamma 2.2 for visual inspection'
        write(u, '(a)') ''
        write(u, '(a)') 'Parallel runs:'
        write(u, '(a)') '  -j, --jobs=N           OpenMP threads converting files at the same time'
        write(u, '(a)') '                         (default 0 = all cores, or $OMP_NUM_THREADS)'
        write(u, '(a)') '      --schedule=MODE    coarray build: static (default) gives image k the'
        write(u, '(a)') '                         files k, k+N, ...; dynamic: next free file'
        write(u, '(a)') ''
        write(u, '(a)') 'Messages:'
        write(u, '(a)') '  -q, --quiet            report errors only'
        write(u, '(a)') '  -v, --verbose          report details for every file'
        write(u, '(a)') '  -h, --help             show this help and exit'
        write(u, '(a)') '  -V, --version          show version information and exit'
        write(u, '(a)') ''
        write(u, '(a)') 'Short options can be combined (-qS) and values attached (-ofits).'
        write(u, '(a)') 'Multi-channel RAW files produce one file per channel (NAME.ch1.fits ...).'
        write(u, '(a)') ''
        write(u, '(a)') 'Examples:'
        write(u, '(a)') '  ' // p // ' *.CR2'
        write(u, '(a)') '  ' // p // ' -o fits/ -a full ~/lights/*.NEF'
        write(u, '(a)') '  ' // p // ' -j 4 -S -o fits/ *.ARW'
        write(u, '(a)') '  cafrun -n 8 ' // p // '-caf -o fits/ *.DNG'
        write(u, '(a)') ''
        write(u, '(a)') 'Exit status: 0 success, 1 some files failed, 2 usage error.'
    end subroutine print_usage

end module m_options
