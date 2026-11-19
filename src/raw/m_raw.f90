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
!   Decode a RAW file with LibRaw into a self-contained frame_t.
!
!   All six LibRaw raw-buffer layouts are accepted (16-bit or float, 1/3/4
!   components).  Floating-point data are scaled linearly so that the largest
!   finite sample maps to 65535.  The LibRaw handle is closed before
!   returning: the frame owns copies of everything it needs.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_raw

    use, intrinsic :: iso_c_binding, only: c_ptr, c_int, c_int16_t, c_float, c_associated, &
                                           c_f_pointer, c_null_char
    use, intrinsic :: iso_fortran_env, only: int16, int32, int64, real64
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use :: m_libraw
    use :: m_strings, only: to_c_string, from_c_chars
    use :: m_platform, only: string_from_c_ptr
    use :: m_frame, only: frame_t, u16_bits, CFA_NONE, CFA_BAYER, CFA_XTRANS

    implicit none (type, external)

    private

    public :: load_raw, libraw_version_string

    integer, parameter, public :: LOAD_OK = 0
    integer, parameter, public :: LOAD_FAILED = 1
    integer, parameter, public :: LOAD_UNSUPPORTED = 2

    !> LibRaw's "unknown" marker for crop margins.
    integer, parameter :: NO_CROP = 65535

contains

    function libraw_version_string() result(text)
        character(len=:), allocatable :: text
        text = string_from_c_ptr(libraw_version())
    end function libraw_version_string

    !> Open, unpack and copy one RAW file.  shot selects the sub-image of
    !> multi-shot files.  status is LOAD_OK, LOAD_FAILED or LOAD_UNSUPPORTED.
    subroutine load_raw(path, shot, frame, status, msg)
        character(len=*), intent(in) :: path
        integer, intent(in) :: shot
        type(frame_t), intent(out) :: frame
        integer, intent(out) :: status
        character(len=:), allocatable, intent(out) :: msg
        type(c_ptr) :: raw
        type(raw_info_t) :: info
        integer(c_int) :: rc

        status = LOAD_FAILED
        msg = ''
        raw = libraw_init(0_c_int)
        if (.not. c_associated(raw)) then
            msg = 'LibRaw initialisation failed'
            return
        end if
        call r2f_raw_set_shot_select(raw, int(shot, c_int))

        rc = libraw_open_file(raw, to_c_string(path))
        if (rc /= 0_c_int) then
            msg = 'cannot open: ' // libraw_error(rc)
        else
            rc = libraw_unpack(raw)
            if (rc /= 0_c_int) then
                msg = 'cannot unpack: ' // libraw_error(rc)
            else
                rc = r2f_raw_get_info(raw, info)
                if (rc /= 0_c_int) then
                    msg = 'cannot read LibRaw metadata'
                else
                    call fill_frame(raw, info, frame, status, msg)
                end if
            end if
        end if
        call libraw_close(raw)
    end subroutine load_raw

    function libraw_error(code) result(text)
        integer(c_int), intent(in) :: code
        character(len=:), allocatable :: text
        text = string_from_c_ptr(libraw_strerror(code))
        if (len(text) == 0) text = 'unknown LibRaw error'
    end function libraw_error

    subroutine fill_frame(raw, info, frame, status, msg)
        type(c_ptr), intent(in) :: raw
        type(raw_info_t), intent(in) :: info
        type(frame_t), intent(inout) :: frame
        integer, intent(out) :: status
        character(len=:), allocatable, intent(inout) :: msg
        integer :: w, h, nch, stride, item_bytes, pitch_elems, needed, astat
        integer(int64) :: pitch, row_bytes, last_index
        logical :: is_float

        ! --- buffer layout -------------------------------------------------
        status = LOAD_UNSUPPORTED
        if (.not. c_associated(info%raw_image) .or. info%raw_kind == RAW_NONE) then
            msg = 'LibRaw exposes no unprocessed sensor buffer for this file'
            return
        end if
        if (info%raw_kind < RAW_U16_MONO .or. info%raw_kind > RAW_F32_4 .or. &
                info%raw_channels < 1 .or. info%raw_channels > 4 .or. &
                info%raw_stride_channels < info%raw_channels) then
            msg = 'unsupported raw buffer layout'
            return
        end if

        status = LOAD_FAILED
        w = info%raw_width
        h = info%raw_height
        nch = info%raw_channels
        stride = info%raw_stride_channels
        if (w <= 0 .or. h <= 0) then
            msg = 'invalid raw dimensions'
            return
        end if
        if (int(w, int64) * int(h, int64) > int(huge(1), int64)) then
            msg = 'raw image too large'
            return
        end if

        is_float = info%raw_kind >= RAW_F32_MONO
        item_bytes = merge(4, 2, is_float)
        row_bytes = int(w, int64) * stride * item_bytes
        pitch = int(info%raw_pitch_bytes, int64)
        if (pitch <= 0_int64) pitch = row_bytes
        if (modulo(pitch, int(item_bytes, int64)) /= 0_int64 .or. pitch < row_bytes) then
            msg = 'invalid raw row stride'
            return
        end if
        pitch_elems = int(pitch / item_bytes)
        last_index = int(pitch_elems, int64) * (h - 1) + int(w, int64) * stride
        if (last_index > int(huge(1), int64)) then
            msg = 'raw buffer exceeds addressable size'
            return
        end if
        needed = int(last_index)

        ! --- pixels ----------------------------------------------------------
        allocate(frame%pixels(w, h, nch), stat=astat)
        if (astat /= 0) then
            msg = 'out of memory'
            return
        end if
        if (is_float) then
            call copy_float(info%raw_image, needed, pitch_elems, stride, frame%pixels)
        else
            call copy_u16(info%raw_image, needed, pitch_elems, stride, frame%pixels)
        end if
        frame%from_float = is_float

        ! --- geometry --------------------------------------------------------
        frame%raw_width = w
        frame%raw_height = h
        frame%channels = nch
        frame%left_margin = info%left_margin
        frame%top_margin = info%top_margin
        frame%active_width = info%active_width
        frame%active_height = info%active_height
        frame%crop_left = info%crop_left
        frame%crop_top = info%crop_top
        frame%crop_width = info%crop_width
        frame%crop_height = info%crop_height
        frame%has_crop = info%crop_width > 0 .and. info%crop_height > 0 .and. &
                                          info%crop_left /= NO_CROP .and. info%crop_top /= NO_CROP

        call fill_meta(info, frame)
        call fill_cfa(raw, info, frame)
        status = LOAD_OK
    end subroutine fill_frame

    subroutine copy_u16(buffer, needed, pitch_elems, stride, pixels)
        type(c_ptr), intent(in) :: buffer
        integer, intent(in) :: needed, pitch_elems, stride
        integer(int16), intent(inout) :: pixels(:, :, :)
        integer(c_int16_t), pointer :: src(:)
        integer :: x, y, c, base

        call c_f_pointer(buffer, src, [needed])
        do y = 1, size(pixels, 2)
            base = (y - 1) * pitch_elems
            do x = 1, size(pixels, 1)
                do c = 1, size(pixels, 3)
                    pixels(x, y, c) = src(base + (x - 1) * stride + c)
                end do
            end do
        end do
    end subroutine copy_u16

    subroutine copy_float(buffer, needed, pitch_elems, stride, pixels)
        type(c_ptr), intent(in) :: buffer
        integer, intent(in) :: needed, pitch_elems, stride
        integer(int16), intent(inout) :: pixels(:, :, :)
        real(c_float), pointer :: src(:)
        real(c_float) :: v, peak
        real(real64) :: scale
        integer :: x, y, c, base

        call c_f_pointer(buffer, src, [needed])
        peak = 0.0_c_float
        do y = 1, size(pixels, 2)
            base = (y - 1) * pitch_elems
            do x = 1, size(pixels, 1)
                do c = 1, size(pixels, 3)
                    v = src(base + (x - 1) * stride + c)
                    if (ieee_is_finite(v)) peak = max(peak, v)
                end do
            end do
        end do

        scale = 0.0_real64
        if (peak > 0.0_c_float) scale = 65535.0_real64 / real(peak, real64)
        do y = 1, size(pixels, 2)
            base = (y - 1) * pitch_elems
            do x = 1, size(pixels, 1)
                do c = 1, size(pixels, 3)
                    v = src(base + (x - 1) * stride + c)
                    if (ieee_is_finite(v) .and. v > 0.0_c_float .and. scale > 0.0_real64) then
                        pixels(x, y, c) = u16_bits(int(min(65535.0_real64, real(v, real64) * scale), int32))
                    else
                        pixels(x, y, c) = 0_int16
                    end if
                end do
            end do
        end do
    end subroutine copy_float

    subroutine fill_meta(info, frame)
        type(raw_info_t), intent(in) :: info
        type(frame_t), intent(inout) :: frame

        associate (m => frame%meta)
            m%exposure = real(info%shutter, real64)
            m%iso = real(info%iso_speed, real64)
            m%aperture = real(info%aperture, real64)
            m%focal_length = real(info%focal_len, real64)
            m%timestamp = int(info%timestamp, int64)
            m%timestamp_subsec = real(info%timestamp_subsec, real64)
            ! LibRaw uses values <= -1000 for "not available".
            m%has_sensor_temp = info%sensor_temp > -999.0_c_float
            m%has_camera_temp = info%camera_temp > -999.0_c_float
            m%sensor_temp = real(info%sensor_temp, real64)
            m%camera_temp = real(info%camera_temp, real64)
            m%black = info%cblack
            m%linear_max = info%linear_max
            m%flip = info%flip
        end associate
        frame%meta%make = from_c_chars(info%make)
        frame%meta%model = from_c_chars(info%model)
        frame%meta%lens = from_c_chars(info%lens)
    end subroutine fill_meta

    subroutine fill_cfa(raw, info, frame)
        type(c_ptr), intent(in) :: raw
        type(raw_info_t), intent(in) :: info
        type(frame_t), intent(inout) :: frame
        integer :: r, c, k

        do k = 1, 4
            if (info%cdesc(k) == c_null_char) then
                frame%cdesc(k:k) = merge('G', '?', k == 4)   ! 3-colour cameras: RGB + G2
            else
                frame%cdesc(k:k) = info%cdesc(k)
            end if
        end do

        if (info%filters == 0 .or. frame%channels /= 1) then
            frame%cfa = CFA_NONE
        else if (info%filters == 9) then
            frame%cfa = CFA_XTRANS
        else
            frame%cfa = CFA_BAYER
            do c = 0, 15
                do r = 0, 15
                    frame%cfa_color(r, c) = int(libraw_color(raw, int(r, c_int), int(c, c_int)))
                end do
            end do
        end if
    end subroutine fill_cfa

end module m_raw
