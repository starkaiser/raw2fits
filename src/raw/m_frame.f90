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
!   In-memory representation of one decoded RAW frame, independent of LibRaw.
!
!   Pixels are stored as unsigned 16-bit values in integer(int16) bit patterns
!   (use u16 / u16_bits to convert), indexed pixels(x, y, channel) with x the
!   fastest index, i.e. in the row order in which they are written to disk.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_frame

    use, intrinsic :: iso_fortran_env, only: int16, int32, int64, real64

    implicit none (type, external)

    private

    public :: frame_t, camera_meta_t, region_t
    public :: u16, u16_bits, cfa_pattern

    !> Sensor areas that can be written.
    integer, parameter, public :: AREA_FULL = 1    !< whole sensor incl. masked pixels
    integer, parameter, public :: AREA_ACTIVE = 2  !< visible area reported by LibRaw
    integer, parameter, public :: AREA_CROP = 3    !< camera default crop

    !> Colour filter array type.
    integer, parameter, public :: CFA_NONE = 0
    integer, parameter, public :: CFA_BAYER = 1
    integer, parameter, public :: CFA_XTRANS = 2

    type :: camera_meta_t
        real(real64) :: exposure = 0.0_real64      !< seconds
        real(real64) :: iso = 0.0_real64
        real(real64) :: aperture = 0.0_real64
        real(real64) :: focal_length = 0.0_real64  !< mm
        logical :: has_sensor_temp = .false.
        logical :: has_camera_temp = .false.
        real(real64) :: sensor_temp = 0.0_real64   !< deg C
        real(real64) :: camera_temp = 0.0_real64   !< deg C
        integer(int64) :: timestamp = 0_int64      !< Unix time, 0 = unknown
        real(real64) :: timestamp_subsec = 0.0_real64
        integer :: black(4) = 0
        integer :: linear_max(4) = 0
        integer :: flip = 0
        ! Fixed-length (sizes as in LibRaw), not deferred-length: see m_strings.
        character(len=64) :: make = '', model = ''
        character(len=128) :: lens = ''
    end type camera_meta_t

    type :: frame_t
        integer :: raw_width = 0, raw_height = 0, channels = 0
        integer :: left_margin = 0, top_margin = 0
        integer :: active_width = 0, active_height = 0
        logical :: has_crop = .false.
        integer :: crop_left = 0, crop_top = 0, crop_width = 0, crop_height = 0
        integer :: cfa = CFA_NONE
        !> CFA colour index at (row, col), relative to the active-area origin,
        !> periodic with period 16 in both directions; -1 = unknown.
        integer :: cfa_color(0:15, 0:15) = -1
        character(len=4) :: cdesc = 'RGBG'          !< colour letters for index 0..3
        logical :: from_float = .false.             !< source was floating point
        integer :: autoscale_factor = 1
        logical :: gamma_applied = .false.
        type(camera_meta_t) :: meta
        integer(int16), allocatable :: pixels(:, :, :)
    end type frame_t

    !> Rectangle of the raw frame (0-based origin) that is written to disk.
    type :: region_t
        integer :: x0 = 0, y0 = 0, width = 0, height = 0
        character(len=8) :: name = 'full'
    end type region_t

contains

    !> Stored bit pattern -> unsigned value 0..65535.
    elemental integer(int32) function u16(bits)
        integer(int16), intent(in) :: bits
        u16 = iand(int(bits, int32), 65535_int32)
    end function u16

    !> Value (clamped to 0..65535) -> stored bit pattern.
    elemental integer(int16) function u16_bits(value)
        integer(int32), intent(in) :: value
        integer(int32) :: v

        v = max(0_int32, min(65535_int32, value))
        if (v > 32767_int32) v = v - 65536_int32
        u16_bits = int(v, int16)
    end function u16_bits

    !> CFA pattern of the first rows x cols pixels of a region, row by row,
    !> e.g. 'RGGB' for rows = cols = 2.
    function cfa_pattern(frame, region, rows, cols) result(pattern)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: rows, cols
        character(len=rows * cols) :: pattern
        integer :: r, c, k, ci, dx, dy

        dx = region%x0 - frame%left_margin
        dy = region%y0 - frame%top_margin
        k = 0
        do r = 0, rows - 1
            do c = 0, cols - 1
                k = k + 1
                ci = frame%cfa_color(modulo(r + dy, 16), modulo(c + dx, 16))
                if (ci >= 0 .and. ci <= 3) then
                    pattern(k:k) = frame%cdesc(ci + 1:ci + 1)
                else
                    pattern(k:k) = '?'
                end if
            end do
        end do
    end function cfa_pattern

end module m_frame
