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
!   Bindings to LibRaw's C API plus the flat metadata struct filled by
!   libraw_shim.c (fields the C API offers no getters for).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_libraw

    use, intrinsic :: iso_c_binding, only: c_ptr, c_char, c_int, c_int32_t, c_int64_t, &
                                           c_float, c_double

    implicit none (type, external)

    private

    public :: raw_info_t
    public :: libraw_init, libraw_open_file, libraw_unpack, libraw_close
    public :: libraw_strerror, libraw_color, libraw_version
    public :: r2f_raw_get_info, r2f_raw_set_shot_select
    public :: RAW_NONE, RAW_U16_MONO, RAW_U16_3, RAW_U16_4, RAW_F32_MONO, RAW_F32_3, RAW_F32_4

    !> Which of LibRaw's six raw buffers was populated by unpack().
    integer(c_int32_t), parameter :: RAW_NONE     = 0_c_int32_t
    integer(c_int32_t), parameter :: RAW_U16_MONO = 1_c_int32_t
    integer(c_int32_t), parameter :: RAW_U16_3    = 2_c_int32_t
    integer(c_int32_t), parameter :: RAW_U16_4    = 3_c_int32_t
    integer(c_int32_t), parameter :: RAW_F32_MONO = 4_c_int32_t
    integer(c_int32_t), parameter :: RAW_F32_3    = 5_c_int32_t
    integer(c_int32_t), parameter :: RAW_F32_4    = 6_c_int32_t

    !> Mirror of struct r2f_raw_info in libraw_shim.c - keep both in sync.
    type, bind(C) :: raw_info_t
        integer(c_int32_t) :: raw_width, raw_height
        integer(c_int32_t) :: active_width, active_height
        integer(c_int32_t) :: left_margin, top_margin
        integer(c_int32_t) :: crop_left, crop_top, crop_width, crop_height
        integer(c_int32_t) :: filters, colors, flip
        integer(c_int32_t) :: raw_kind, raw_channels, raw_stride_channels, raw_pitch_bytes
        integer(c_int64_t) :: timestamp
        real(c_double) :: timestamp_subsec
        real(c_float) :: shutter, iso_speed, aperture, focal_len
        real(c_float) :: sensor_temp, camera_temp
        integer(c_int32_t) :: cblack(4), linear_max(4)
        character(kind=c_char) :: make(64), model(64), lens(128), cdesc(5)
        type(c_ptr) :: raw_image
    end type raw_info_t

    interface
        function libraw_init(flags) bind(C, name='libraw_init') result(raw)
            import :: c_ptr, c_int
            implicit none
            integer(c_int), value :: flags
            type(c_ptr) :: raw
        end function libraw_init

        function libraw_open_file(raw, filename) bind(C, name='libraw_open_file') result(status)
            import :: c_ptr, c_char, c_int
            implicit none
            type(c_ptr), value :: raw
            character(kind=c_char), intent(in) :: filename(*)
            integer(c_int) :: status
        end function libraw_open_file

        function libraw_unpack(raw) bind(C, name='libraw_unpack') result(status)
            import :: c_ptr, c_int
            implicit none
            type(c_ptr), value :: raw
            integer(c_int) :: status
        end function libraw_unpack

        subroutine libraw_close(raw) bind(C, name='libraw_close')
            import :: c_ptr
            implicit none
            type(c_ptr), value :: raw
        end subroutine libraw_close

        function libraw_strerror(error_code) bind(C, name='libraw_strerror') result(message)
            import :: c_ptr, c_int
            implicit none
            integer(c_int), value :: error_code
            type(c_ptr) :: message
        end function libraw_strerror

        !> CFA colour index at (row, col) relative to the active-area origin.
        function libraw_color(raw, row, col) bind(C, name='libraw_COLOR') result(color_index)
            import :: c_ptr, c_int
            implicit none
            type(c_ptr), value :: raw
            integer(c_int), value :: row, col
            integer(c_int) :: color_index
        end function libraw_color

        function libraw_version() bind(C, name='libraw_version') result(text)
            import :: c_ptr
            implicit none
            type(c_ptr) :: text
        end function libraw_version

        function r2f_raw_get_info(raw, info) bind(C, name='r2f_raw_get_info') result(status)
            import :: c_ptr, c_int, raw_info_t
            implicit none
            type(c_ptr), value :: raw
            type(raw_info_t), intent(out) :: info
            integer(c_int) :: status
        end function r2f_raw_get_info

        subroutine r2f_raw_set_shot_select(raw, shot) bind(C, name='r2f_raw_set_shot_select')
            import :: c_ptr, c_int
            implicit none
            type(c_ptr), value :: raw
            integer(c_int), value :: shot
        end subroutine r2f_raw_set_shot_select
    end interface

end module m_libraw
