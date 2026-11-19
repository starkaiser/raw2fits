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
!   Output file naming and format dispatch.  Files are written to a
!   temporary '<name>.part' and renamed when complete, so an interrupted run
!   never leaves a truncated file under the final name.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_output

    use :: m_strings, only: path_basename, path_dirname, path_stem, path_join, str
    use :: m_options, only: options_t, FMT_TIFF, FMT_PGM
    use :: m_frame, only: frame_t, region_t
    use :: m_fits_writer, only: write_fits
    use :: m_tiff_writer, only: write_tiff
    use :: m_pgm_writer, only: write_pgm
    use :: m_platform, only: rename_file, remove_file, path_exists

    implicit none (type, external)

    private

    public :: output_stem, output_path, output_extension, outputs_exist, write_output

contains

    !> Default or user-selected extension (without the dot).
    function output_extension(opts) result(ext)
        type(options_t), intent(in) :: opts
        character(len=:), allocatable :: ext

        if (len_trim(opts%ext) > 0) then
            ext = trim(opts%ext)
            return
        end if
        select case (opts%format)
        case (FMT_TIFF)
            ext = 'tiff'
        case (FMT_PGM)
            ext = 'pgm'
        case default
            ext = 'fits'
        end select
    end function output_extension

    !> Output path without channel suffix and extension:
    !> [outdir or input dir]/name[.rawext][-shot]
    function output_stem(input, opts) result(stem)
        character(len=*), intent(in) :: input
        type(options_t), intent(in) :: opts
        character(len=:), allocatable :: stem, name, dir

        name = path_basename(input)
        if (.not. opts%keep_ext) name = path_stem(name)
        if (opts%shot > 0) name = name // '-' // str(opts%shot)
        dir = path_dirname(input)
        if (len_trim(opts%outdir) > 0) dir = trim(opts%outdir)
        stem = path_join(dir, name)
    end function output_stem

    !> stem.ext for single-channel data, stem.chN.ext otherwise.
    function output_path(stem, channel, channels, ext) result(path)
        character(len=*), intent(in) :: stem, ext
        integer, intent(in) :: channel, channels
        character(len=:), allocatable :: path

        if (channels > 1) then
            path = stem // '.ch' // str(channel) // '.' // ext
        else
            path = stem // '.' // ext
        end if
    end function output_path

    !> True if a previous run already produced output for this stem.
    logical function outputs_exist(stem, ext)
        character(len=*), intent(in) :: stem, ext
        outputs_exist = path_exists(output_path(stem, 1, 1, ext))
        if (.not. outputs_exist) outputs_exist = path_exists(output_path(stem, 1, 2, ext))
    end function outputs_exist

    subroutine write_output(frame, region, channel, format, path, ok, msg)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: channel, format
        character(len=*), intent(in) :: path
        logical, intent(out) :: ok
        character(len=:), allocatable, intent(out) :: msg
        character(len=:), allocatable :: tmp

        tmp = path // '.part'
        select case (format)
        case (FMT_TIFF)
            call write_tiff(frame, region, channel, tmp, ok, msg)
        case (FMT_PGM)
            call write_pgm(frame, region, channel, tmp, ok, msg)
        case default
            call write_fits(frame, region, channel, tmp, ok, msg)
        end select

        if (ok) then
            if (.not. rename_file(tmp, path)) then
                ok = .false.
                msg = 'cannot rename ' // tmp // ' to ' // path
            end if
        end if
        if (.not. ok) then
            if (path_exists(tmp)) then
                if (.not. remove_file(tmp)) msg = msg // ' (could not remove ' // tmp // ')'
            end if
        end if
    end subroutine write_output

end module m_output
