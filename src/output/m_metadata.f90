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
!   Maps frame metadata to FITS keywords (also used for AstroTIFF) and to
!   PGM comment lines.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_metadata

    use, intrinsic :: iso_fortran_env, only: real64
    use :: m_frame, only: frame_t, region_t, cfa_pattern, CFA_BAYER, CFA_XTRANS
    use :: m_fits_header, only: fits_header_t
    use :: m_time, only: unix_to_iso8601, unix_to_julian_date
    use :: m_strings, only: str
    use :: m_config, only: APP_NAME, APP_VERSION

    implicit none (type, external)

    private

    public :: build_header, pgm_comments

contains

    !> Header for one channel of the given region.  for_fits adds BZERO/BSCALE
    !> (unsigned 16-bit FITS convention); TIFF stores real unsigned samples.
    subroutine build_header(frame, region, channel, for_fits, hdr)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        integer, intent(in) :: channel
        logical, intent(in) :: for_fits
        type(fits_header_t), intent(out) :: hdr
        real(real64) :: temp
        logical :: has_temp
        integer :: k
        character(len=8), parameter :: ped_keys(4) = &
            [character(len=8) :: 'PEDESTAL', 'PEDESTA2', 'PEDESTA3', 'PEDESTA4']
        character(len=8), parameter :: max_keys(4) = &
            [character(len=8) :: 'DATAMAX', 'DATAMAX2', 'DATAMAX3', 'DATAMAX4']

        associate (m => frame%meta)
            call hdr%add_logical('SIMPLE', .true., 'file conforms to the FITS standard')
            call hdr%add_int('BITPIX', 16, '16-bit integer samples')
            call hdr%add_int('NAXIS', 2, 'two-dimensional image')
            call hdr%add_int('NAXIS1', region%width, 'image width [pixels]')
            call hdr%add_int('NAXIS2', region%height, 'image height [pixels]')
            if (for_fits) then
                call hdr%add_int('BZERO', 32768, 'unsigned 16-bit: value = stored + 32768')
                call hdr%add_int('BSCALE', 1, 'no scaling')
            end if

            call hdr%add_real('EXPTIME', m%exposure, 'exposure time [s]')
            if (m%timestamp /= 0) then
                call hdr%add_string('DATE-OBS', unix_to_iso8601(m%timestamp, m%timestamp_subsec), &
                                                        'start of exposure (camera clock)')
                call hdr%add_real('JD', unix_to_julian_date(m%timestamp, m%timestamp_subsec), &
                                                    'Julian date, start of exposure', fmt='(f20.8)')
            end if

            has_temp = .true.
            if (m%has_sensor_temp) then
                temp = m%sensor_temp
            else if (m%has_camera_temp) then
                temp = m%camera_temp
            else
                has_temp = .false.
                temp = 0.0_real64
            end if
            if (has_temp) call hdr%add_real('CCD-TEMP', temp, 'sensor/camera temperature [C]')

            if (m%iso > 0.0_real64) then
                call hdr%add_int('ISOSPEED', nint(m%iso), 'ISO speed')
                call hdr%add_int('GAIN', nint(m%iso), 'camera gain setting (ISO)')
            end if
            if (any(m%black /= 0)) then
                do k = 1, 4
                    call hdr%add_int(ped_keys(k), m%black(k), 'black level, channel ' // str(k))
                end do
            end if
            if (any(m%linear_max /= 0)) then
                do k = 1, 4
                    call hdr%add_int(max_keys(k), m%linear_max(k), 'max. linear value, channel ' // str(k))
                end do
            end if
            if (m%aperture > 0.0_real64) call hdr%add_real('APERTURE', m%aperture, 'lens f-number')
            if (m%focal_length > 0.0_real64) &
                call hdr%add_int('FOCALLEN', nint(m%focal_length), 'focal length [mm]')
            call hdr%add_string('CAMMAKER', trim(frame%meta%make), 'camera manufacturer')
            call hdr%add_string('INSTRUME', trim(frame%meta%model), 'camera model')
            call hdr%add_string('TELESCOP', trim(frame%meta%lens), 'lens')
        end associate

        if (frame%channels > 1) then
            call hdr%add_int('RAWCHAN', channel, 'raw channel plane (1-based)')
            call hdr%add_int('RAWCHNS', frame%channels, 'number of raw channels')
        end if

        if (frame%cfa == CFA_BAYER) then
            call hdr%add_string('BAYERPAT', cfa_pattern(frame, region, 2, 2), 'CFA pattern, top-left 2x2')
            call hdr%add_string('FILT-PAT', cfa_pattern(frame, region, 8, 2), 'CFA pattern, 8 rows x 2 cols')
            call hdr%add_int('XBAYROFF', 0, 'x offset of the CFA pattern')
            call hdr%add_int('YBAYROFF', 0, 'y offset of the CFA pattern')
        else if (frame%cfa == CFA_XTRANS) then
            call hdr%add_comment('X-Trans 6x6 CFA data; not representable as a 2x2 BAYERPAT.')
        end if
        call hdr%add_string('ROWORDER', 'TOP-DOWN', 'first stored row is the top of the image')
        call hdr%add_int('IMG_FLIP', frame%meta%flip, 'LibRaw orientation flag (not applied)')
        call hdr%add_string('RAWAREA', trim(region%name), 'sensor area written')
        call hdr%add_int('RAWX0', region%x0, 'x origin of the area on the sensor')
        call hdr%add_int('RAWY0', region%y0, 'y origin of the area on the sensor')
        call hdr%add_string('SWCREATE', APP_NAME // ' ' // APP_VERSION // ' (LibRaw)', &
                                                'conversion software')

        if (frame%from_float) &
            call hdr%add_comment('Floating-point RAW data scaled linearly to 0..65535.')
        if (frame%autoscale_factor > 1) &
            call hdr%add_history('Autoscaled by integer factor ' // str(frame%autoscale_factor) // '.')
        if (frame%gamma_applied) &
            call hdr%add_history('Gamma 2.2 applied: data are no longer linear.')
        call hdr%add_comment('Unprocessed sensor data decoded by LibRaw: no demosaicing,')
        call hdr%add_comment('white balance or colour conversion. DATE-OBS assumes the camera')
        call hdr%add_comment('clock was set to the time zone of the converting computer.')
        call hdr%finish()
    end subroutine build_header

    !> '# KEY=value' lines for the PGM header.
    function pgm_comments(frame, channel) result(text)
        type(frame_t), intent(in) :: frame
        integer, intent(in) :: channel
        character(len=:), allocatable :: text

        text = ''
        associate (m => frame%meta)
            call add('EXPTIME=' // str(m%exposure))
            if (m%timestamp /= 0) call add('DATE-OBS=' // unix_to_iso8601(m%timestamp, m%timestamp_subsec))
            if (m%has_sensor_temp) call add('CCD-TEMP=' // str(m%sensor_temp))
            if (m%has_camera_temp) call add('CAM-TEMP=' // str(m%camera_temp))
            call add('ISOSPEED=' // str(nint(m%iso)))
            call add('APERTURE=' // str(m%aperture))
            call add('FOCALLEN=' // str(nint(m%focal_length)))
            call add('MAKE=' // trim(frame%meta%make))
            call add('MODEL=' // trim(frame%meta%model))
            call add('LENS=' // trim(frame%meta%lens))
        end associate
        if (frame%channels > 1) call add('RAW_CHANNEL=' // str(channel) // '/' // str(frame%channels))
        if (frame%from_float) call add('INPUT_FLOAT_DATA=scaled linearly to 0..65535')

    contains

        subroutine add(line)
            character(len=*), intent(in) :: line
            text = text // '# ' // line // new_line('a')
        end subroutine add

    end function pgm_comments

end module m_metadata
