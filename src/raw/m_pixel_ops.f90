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
!   Operations on decoded frames: area selection and optional pixel processing.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_pixel_ops

    use, intrinsic :: iso_fortran_env, only: int16, real64
    use :: m_frame, only: frame_t, region_t, u16, u16_bits, AREA_FULL, AREA_CROP

    implicit none (type, external)

    private

    public :: select_region, autoscale, apply_gamma

contains

    !> Rectangle to write for the requested area.  A missing or out-of-range
    !> default crop falls back to the active area (fell_back = .true.).
    subroutine select_region(frame, area, region, fell_back, ok)
        type(frame_t), intent(in) :: frame
        integer, intent(in) :: area
        type(region_t), intent(out) :: region
        logical, intent(out) :: fell_back, ok

        fell_back = .false.
        select case (area)
        case (AREA_FULL)
            region = region_t(0, 0, frame%raw_width, frame%raw_height, 'full')
        case (AREA_CROP)
            region = region_t(frame%crop_left, frame%crop_top, frame%crop_width, frame%crop_height, 'crop')
            if (.not. (frame%has_crop .and. inside(region))) then
                fell_back = .true.
                region = active_region()
            end if
        case default
            region = active_region()
        end select
        ok = inside(region)

    contains

        type(region_t) function active_region()
            active_region = region_t(frame%left_margin, frame%top_margin, &
                                                              frame%active_width, frame%active_height, 'active')
        end function active_region

        logical function inside(r)
            type(region_t), intent(in) :: r
            inside = r%x0 >= 0 .and. r%y0 >= 0 .and. r%width > 0 .and. r%height > 0 .and. &
                              r%x0 + r%width <= frame%raw_width .and. r%y0 + r%height <= frame%raw_height
        end function inside

    end subroutine select_region

    !> Multiply low-range data by the integer factor 65536 / peak (saturating),
    !> as in the original LibRaw sample.  factor = 1 when nothing was done.
    subroutine autoscale(frame, factor, peak)
        type(frame_t), intent(inout) :: frame
        integer, intent(out) :: factor, peak
        integer :: x, y, c

        peak = 0
        do c = 1, size(frame%pixels, 3)
            do y = 1, size(frame%pixels, 2)
                do x = 1, size(frame%pixels, 1)
                    peak = max(peak, u16(frame%pixels(x, y, c)))
                end do
            end do
        end do

        factor = 1
        if (peak <= 0 .or. peak >= 32768) return
        factor = 65536 / peak
        do c = 1, size(frame%pixels, 3)
            do y = 1, size(frame%pixels, 2)
                do x = 1, size(frame%pixels, 1)
                    frame%pixels(x, y, c) = u16_bits(min(65535, u16(frame%pixels(x, y, c)) * factor))
                end do
            end do
        end do
        frame%autoscale_factor = factor
    end subroutine autoscale

    !> Gamma 2.2 (visual inspection only - destroys linearity).
    subroutine apply_gamma(frame)
        type(frame_t), intent(inout) :: frame
        integer(int16) :: lut(0:65535)
        real(real64) :: g
        integer :: v, x, y, c

        lut(0) = 0_int16
        do v = 1, 65535
            g = 65536.0_real64 * (real(v, real64) / 65535.0_real64)**(1.0_real64 / 2.2_real64)
            lut(v) = u16_bits(min(65535, int(g)))
        end do
        do c = 1, size(frame%pixels, 3)
            do y = 1, size(frame%pixels, 2)
                do x = 1, size(frame%pixels, 1)
                    frame%pixels(x, y, c) = lut(u16(frame%pixels(x, y, c)))
                end do
            end do
        end do
        frame%gamma_applied = .true.
    end subroutine apply_gamma

end module m_pixel_ops
