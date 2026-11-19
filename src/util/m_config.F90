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
!   Build information. R2F_VERSION and R2F_BACKEND are set by the Makefile
!   (from the VERSION file and the BACKEND option).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================


#ifndef R2F_VERSION
#define R2F_VERSION "dev"
#endif
#ifndef R2F_BACKEND
#define R2F_BACKEND "threads"
#endif

module m_config

    implicit none (type, external)

    private

    character(len=*), parameter, public :: APP_NAME    = 'raw2fits'
    character(len=*), parameter, public :: APP_VERSION = R2F_VERSION
    character(len=*), parameter, public :: APP_BACKEND = R2F_BACKEND

end module m_config
