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
!   Uncompressed 16-bit greyscale little-endian TIFF with the FITS cards in
!   the ImageDescription tag (AstroTIFF convention).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_tiff_writer

    use, intrinsic :: iso_fortran_env, only: int64
    use :: m_frame, only: frame_t, region_t
    use :: m_fits_header, only: fits_header_t
    use :: m_metadata, only: build_header
    use :: m_bytes, only: pack_row, put_u16_le, put_u32_le
    use :: m_time, only: local_tiff_datetime

    implicit none (type, external)

    private

    public :: write_tiff

    integer, parameter :: TIFF_ASCII = 2, TIFF_SHORT = 3, TIFF_LONG = 4, TIFF_RATIONAL = 5
    integer, parameter :: N_ENTRIES = 16
    integer(int64), parameter :: MAX_CLASSIC_TIFF = 4294967295_int64

contains

    subroutine write_tiff(frame, region, channel, path, ok, msg)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: channel
        character(len=*), intent(in) :: path
        logical, intent(out) :: ok
        character(len=:), allocatable, intent(out) :: msg
        type(fits_header_t) :: hdr
        character(len=:), allocatable :: desc, head, row_bytes
        character(len=256) :: iomsg
        integer :: desc_len, desc_off, dt_off, xres_off, yres_off, pix_off
        integer :: pos, unit, ios, y, x0, x1
        integer(int64) :: image_bytes

        ok = .false.
        msg = ''
        call build_header(frame, region, channel, .false., hdr)
        desc = hdr%as_text()

        ! File layout (0-based offsets): header | IFD | description | DateTime |
        ! XResolution | YResolution | pixels.
        desc_len = len(desc) + 1                           ! including NUL
        desc_off = 8 + 2 + 12 * N_ENTRIES + 4
        dt_off = desc_off + desc_len + modulo(desc_len, 2)   ! keep word alignment
        xres_off = dt_off + 20
        yres_off = xres_off + 8
        pix_off = yres_off + 8
        image_bytes = 2_int64 * region%width * region%height
        if (image_bytes + pix_off > MAX_CLASSIC_TIFF) then
            msg = 'image too large for a classic TIFF file'
            return
        end if

        head = repeat(achar(0), pix_off)
        head(1:4) = 'II' // achar(42) // achar(0)
        call put_u32_le(head, 5, 8_int64)                  ! offset of first IFD
        call put_u16_le(head, 9, N_ENTRIES)
        pos = 11
        call ifd_entry(254, TIFF_LONG, 1, 0_int64)                         ! NewSubfileType
        call ifd_entry(256, TIFF_LONG, 1, int(region%width, int64))        ! ImageWidth
        call ifd_entry(257, TIFF_LONG, 1, int(region%height, int64))       ! ImageLength
        call ifd_entry(258, TIFF_SHORT, 1, 16_int64)                       ! BitsPerSample
        call ifd_entry(259, TIFF_SHORT, 1, 1_int64)                        ! Compression: none
        call ifd_entry(262, TIFF_SHORT, 1, 1_int64)                        ! BlackIsZero
        call ifd_entry(270, TIFF_ASCII, desc_len, int(desc_off, int64))    ! ImageDescription
        call ifd_entry(273, TIFF_LONG, 1, int(pix_off, int64))             ! StripOffsets
        call ifd_entry(277, TIFF_SHORT, 1, 1_int64)                        ! SamplesPerPixel
        call ifd_entry(278, TIFF_LONG, 1, int(region%height, int64))       ! RowsPerStrip
        call ifd_entry(279, TIFF_LONG, 1, image_bytes)                     ! StripByteCounts
        call ifd_entry(282, TIFF_RATIONAL, 1, int(xres_off, int64))        ! XResolution
        call ifd_entry(283, TIFF_RATIONAL, 1, int(yres_off, int64))        ! YResolution
        call ifd_entry(284, TIFF_SHORT, 1, 1_int64)                        ! PlanarConfiguration
        call ifd_entry(296, TIFF_SHORT, 1, 2_int64)                        ! ResolutionUnit: inch
        call ifd_entry(306, TIFF_ASCII, 20, int(dt_off, int64))            ! DateTime
        call put_u32_le(head, pos, 0_int64)                                ! no next IFD

        head(desc_off + 1:desc_off + len(desc)) = desc
        head(dt_off + 1:dt_off + 19) = local_tiff_datetime()
        call put_u32_le(head, xres_off + 1, 300_int64)
        call put_u32_le(head, xres_off + 5, 1_int64)
        call put_u32_le(head, yres_off + 1, 300_int64)
        call put_u32_le(head, yres_off + 5, 1_int64)

        open(newunit=unit, file=path, status='replace', access='stream', form='unformatted', &
                  action='write', iostat=ios, iomsg=iomsg)
        if (ios /= 0) then
            msg = trim(iomsg)
            return
        end if
        write(unit, iostat=ios, iomsg=iomsg) head

        x0 = region%x0 + 1
        x1 = region%x0 + region%width
        allocate(character(len=2 * region%width) :: row_bytes)
        do y = region%y0 + 1, region%y0 + region%height
            if (ios /= 0) exit
            call pack_row(frame%pixels(x0:x1, y, channel), .false., .false., row_bytes)
            write(unit, iostat=ios, iomsg=iomsg) row_bytes
        end do

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

    contains

        !> 12-byte IFD entry; SHORT values are left-justified in the value field.
        subroutine ifd_entry(tag, field_type, count, value)
            integer, intent(in) :: tag, field_type, count
            integer(int64), intent(in) :: value

            call put_u16_le(head, pos, tag)
            call put_u16_le(head, pos + 2, field_type)
            call put_u32_le(head, pos + 4, int(count, int64))
            call put_u32_le(head, pos + 8, value)
            pos = pos + 12
        end subroutine ifd_entry

    end subroutine write_tiff

end module m_tiff_writer
