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
!   FITS writer: BITPIX = 16 with BZERO = 32768 (standard unsigned 16-bit).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_fits_writer

    use, intrinsic :: iso_fortran_env, only: int64
    use :: m_frame, only: frame_t, region_t
    use :: m_fits_header, only: fits_header_t, FITS_BLOCK
    use :: m_metadata, only: build_header
    use :: m_bytes, only: pack_row

    implicit none (type, external)

    private

    public :: write_fits

contains

    subroutine write_fits(frame, region, channel, path, ok, msg)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: channel
        character(len=*), intent(in) :: path
        logical, intent(out) :: ok
        character(len=:), allocatable, intent(out) :: msg
        type(fits_header_t) :: hdr
        character(len=:), allocatable :: row_bytes
        character(len=256) :: iomsg
        integer :: unit, ios, y, x0, x1
        integer(int64) :: data_bytes, pad

        ok = .false.
        msg = ''
        call build_header(frame, region, channel, .true., hdr)

        open(newunit=unit, file=path, status='replace', access='stream', form='unformatted', &
                  action='write', iostat=ios, iomsg=iomsg)
        if (ios /= 0) then
            msg = trim(iomsg)
            return
        end if

        write(unit, iostat=ios, iomsg=iomsg) hdr%as_block()

        ! Data: rows top to bottom, big-endian, offset binary.
        x0 = region%x0 + 1
        x1 = region%x0 + region%width
        allocate(character(len=2 * region%width) :: row_bytes)
        do y = region%y0 + 1, region%y0 + region%height
            if (ios /= 0) exit
            call pack_row(frame%pixels(x0:x1, y, channel), .true., .true., row_bytes)
            write(unit, iostat=ios, iomsg=iomsg) row_bytes
        end do

        ! Pad the data unit to a whole number of 2880-byte blocks.
        if (ios == 0) then
            data_bytes = 2_int64 * region%width * region%height
            pad = modulo(-data_bytes, int(FITS_BLOCK, int64))
            if (pad > 0_int64) write(unit, iostat=ios, iomsg=iomsg) repeat(achar(0), int(pad))
        end if

        if (ios /= 0) then
            msg = trim(iomsg)
            close(unit)
            return
        end if
        close(unit, iostat=ios, iomsg=iomsg)
        if (ios /= 0) then
            msg = trim(iomsg)
            return
        end if
        ok = .true.
    end subroutine write_fits

end module m_fits_writer
