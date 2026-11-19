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
!   Date/time conversions (exact integer arithmetic, proleptic Gregorian).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_time

    use, intrinsic :: iso_fortran_env, only: int64, real64

    implicit none (type, external)

    private

    public :: civil_from_days, unix_to_iso8601, unix_to_julian_date, local_tiff_datetime

    real(real64), parameter :: JD_UNIX_EPOCH = 2440587.5_real64

contains

    !> Days since 1970-01-01 -> calendar date (H. Hinnant's algorithm).
    subroutine civil_from_days(days, year, month, day)
        integer(int64), intent(in) :: days
        integer, intent(out) :: year, month, day
        integer(int64) :: z, era, doe, yoe, y, doy, mp

        z = days + 719468_int64
        if (z >= 0_int64) then
            era = z / 146097_int64
        else
            era = (z - 146096_int64) / 146097_int64
        end if
        doe = z - era * 146097_int64
        yoe = (doe - doe / 1460_int64 + doe / 36524_int64 - doe / 146096_int64) / 365_int64
        y = yoe + era * 400_int64
        doy = doe - (365_int64 * yoe + yoe / 4_int64 - yoe / 100_int64)
        mp = (5_int64 * doy + 2_int64) / 153_int64
        day = int(doy - (153_int64 * mp + 2_int64) / 5_int64 + 1_int64)
        if (mp < 10_int64) then
            month = int(mp + 3_int64)
        else
            month = int(mp - 9_int64)
        end if
        if (month <= 2) y = y + 1_int64
        year = int(y)
    end subroutine civil_from_days

    !> Unix time -> 'YYYY-MM-DDThh:mm:ss.sss' (UTC).
    function unix_to_iso8601(seconds, subsec) result(text)
        integer(int64), intent(in) :: seconds
        real(real64), intent(in) :: subsec
        character(len=23) :: text
        integer(int64) :: total_ms, days, ms
        integer :: year, month, day, hh, mm, ss, msec

        total_ms = seconds * 1000_int64 + nint(subsec * 1000.0_real64, int64)
        ms = modulo(total_ms, 86400000_int64)
        days = (total_ms - ms) / 86400000_int64
        call civil_from_days(days, year, month, day)
        hh = int(ms / 3600000_int64)
        mm = int(mod(ms, 3600000_int64) / 60000_int64)
        ss = int(mod(ms, 60000_int64) / 1000_int64)
        msec = int(mod(ms, 1000_int64))
        write(text, '(i4.4,"-",i2.2,"-",i2.2,"T",i2.2,":",i2.2,":",i2.2,".",i3.3)') &
            year, month, day, hh, mm, ss, msec
    end function unix_to_iso8601

    pure real(real64) function unix_to_julian_date(seconds, subsec) result(jd)
        integer(int64), intent(in) :: seconds
        real(real64), intent(in) :: subsec
        jd = JD_UNIX_EPOCH + (real(seconds, real64) + subsec) / 86400.0_real64
    end function unix_to_julian_date

    !> Current local time as TIFF DateTime 'YYYY:MM:DD hh:mm:ss'.
    function local_tiff_datetime() result(text)
        character(len=19) :: text
        integer :: v(8)

        call date_and_time(values=v)
        write(text, '(i4.4,":",i2.2,":",i2.2," ",i2.2,":",i2.2,":",i2.2)') &
            v(1), v(2), v(3), v(5), v(6), v(7)
    end function local_tiff_datetime

end module m_time
