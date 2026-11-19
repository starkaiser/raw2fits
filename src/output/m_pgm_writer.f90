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
!   16-bit binary PGM (P5) writer with metadata comment lines.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_pgm_writer

    use :: m_frame, only: frame_t, region_t
    use :: m_metadata, only: pgm_comments
    use :: m_bytes, only: pack_row
    use :: m_strings, only: str

    implicit none (type, external)

    private

    public :: write_pgm

contains

    subroutine write_pgm(frame, region, channel, path, ok, msg)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: channel
        character(len=*), intent(in) :: path
        logical, intent(out) :: ok
        character(len=:), allocatable, intent(out) :: msg
        character(len=:), allocatable :: head, row_bytes
        character(len=256) :: iomsg
        character(len=1), parameter :: lf = achar(10)
        integer :: unit, ios, y, x0, x1

        ok = .false.
        msg = ''
        head = 'P5' // lf // pgm_comments(frame, channel) // &
                      str(region%width) // ' ' // str(region%height) // lf // '65535' // lf

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
            call pack_row(frame%pixels(x0:x1, y, channel), .true., .false., row_bytes)
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
    end subroutine write_pgm

end module m_pgm_writer
