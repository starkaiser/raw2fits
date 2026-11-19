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
!   Console messages. Errors are always printed; progress messages unless
!   --quiet; details only with --verbose. While files are being converted
!   in parallel, every line is tagged with the thread or coarray image that
!   wrote it ([2/8]). Each message is one WRITE statement, which libgfortran
!   serialises, so lines from different threads never mix.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_log

    use, intrinsic :: iso_fortran_env, only: output_unit, error_unit
    use :: m_config, only: APP_NAME

    implicit none (type, external)

    private

    integer, parameter, public :: LOG_QUIET = 0, LOG_NORMAL = 1, LOG_VERBOSE = 2

    integer, save :: level = LOG_NORMAL
    character(len=32), save :: tag = ''
    !$omp threadprivate(tag)

    public :: log_set_level, log_set_tag
    public :: log_info, log_detail, log_warn, log_error

contains

    subroutine log_set_level(verbosity)
        integer, intent(in) :: verbosity
        level = verbosity
    end subroutine log_set_level

    !> Name printed in front of this thread's / image's messages, e.g. '[2/8]'.
    subroutine log_set_tag(text)
        character(len=*), intent(in) :: text
        tag = text
    end subroutine log_set_tag

    function prefix() result(text)
        character(len=:), allocatable :: text
        if (len_trim(tag) > 0) then
            text = trim(tag) // ' '
        else
            text = ''
        end if
    end function prefix

    !> Normal progress message (suppressed by --quiet).
    subroutine log_info(message)
        character(len=*), intent(in) :: message
        if (level < LOG_NORMAL) return
        write(output_unit, '(a)') prefix() // message
        flush(output_unit)
    end subroutine log_info

    !> Detail shown only with --verbose.
    subroutine log_detail(message)
        character(len=*), intent(in) :: message
        if (level < LOG_VERBOSE) return
        write(output_unit, '(a)') prefix() // message
        flush(output_unit)
    end subroutine log_detail

    subroutine log_warn(message)
        character(len=*), intent(in) :: message
        if (level < LOG_NORMAL) return
        write(error_unit, '(a)') prefix() // APP_NAME // ': warning: ' // message
        flush(error_unit)
    end subroutine log_warn

    !> Errors are always shown.
    subroutine log_error(message)
        character(len=*), intent(in) :: message
        write(error_unit, '(a)') prefix() // APP_NAME // ': ' // message
        flush(error_unit)
    end subroutine log_error

end module m_log
