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
!   Byte-level packing for the binary writers (endianness independent).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_bytes

    use, intrinsic :: iso_fortran_env, only: int16, int32, int64

    implicit none (type, external)

    private

    public :: pack_row, put_u16_le, put_u32_le

contains

    !> Pack unsigned 16-bit samples into bytes(1:2*size(row)).
    !> offset_binary subtracts 32768 (the FITS BZERO convention).
    subroutine pack_row(row, big_endian, offset_binary, bytes)
        integer(int16), intent(in) :: row(:)
        logical, intent(in) :: big_endian, offset_binary
        character(len=*), intent(inout) :: bytes
        integer :: k, v, hi, lo

        do k = 1, size(row)
            v = iand(int(row(k), int32), 65535_int32)
            if (offset_binary) v = ieor(v, 32768)
            hi = ishft(v, -8)
            lo = iand(v, 255)
            if (big_endian) then
                bytes(2*k - 1:2*k - 1) = achar(hi)
                bytes(2*k:2*k) = achar(lo)
            else
                bytes(2*k - 1:2*k - 1) = achar(lo)
                bytes(2*k:2*k) = achar(hi)
            end if
        end do
    end subroutine pack_row

    !> Little-endian 16-bit value at 1-based byte position pos.
    subroutine put_u16_le(buf, pos, value)
        character(len=*), intent(inout) :: buf
        integer, intent(in) :: pos, value

        buf(pos:pos) = achar(iand(value, 255))
        buf(pos + 1:pos + 1) = achar(iand(ishft(value, -8), 255))
    end subroutine put_u16_le

    !> Little-endian 32-bit unsigned value at 1-based byte position pos.
    subroutine put_u32_le(buf, pos, value)
        character(len=*), intent(inout) :: buf
        integer, intent(in) :: pos
        integer(int64), intent(in) :: value
        integer :: k

        do k = 0, 3
            buf(pos + k:pos + k) = achar(int(iand(ishft(value, -8 * k), 255_int64)))
        end do
    end subroutine put_u32_le

end module m_bytes
