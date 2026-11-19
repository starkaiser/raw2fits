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
!   Fortran interface to r2f_platform.c, the only operating-system specific
!   code: which OS we run on, and the file-system calls standard Fortran
!   lacks (mkdir -p, rename that replaces the target, remove, stat). The
!   wrappers take and return ordinary Fortran strings.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_platform

    use, intrinsic :: iso_c_binding, only: c_char, c_int, c_ptr, c_size_t, c_null_char, &
                                           c_associated, c_f_pointer

    implicit none (type, external)

    private

    !> OS_UNIX: GNU/Linux, FreeBSD and other POSIX systems (same code paths).
    integer, parameter, public :: OS_UNIX = 1, OS_MACOS = 2, OS_WINDOWS = 3

    integer(c_int), parameter :: PATH_NONE = 0_c_int
    integer(c_int), parameter :: PATH_DIR  = 2_c_int

    public :: os, path_exists, is_directory, make_directory, rename_file, remove_file
    public :: string_from_c_ptr

    interface
        pure function r2f_platform() bind(C, name="r2f_platform") result(id)
            import :: c_int
            integer(c_int) :: id
        end function r2f_platform

        function r2f_mkdir_p(path) bind(C, name="r2f_mkdir_p") result(status)
            import :: c_char, c_int
            character(kind=c_char), intent(in) :: path(*)
            integer(c_int) :: status
        end function r2f_mkdir_p

        function r2f_rename(from, to) bind(C, name="r2f_rename") result(status)
            import :: c_char, c_int
            character(kind=c_char), intent(in) :: from(*), to(*)
            integer(c_int) :: status
        end function r2f_rename

        function r2f_remove(path) bind(C, name="r2f_remove") result(status)
            import :: c_char, c_int
            character(kind=c_char), intent(in) :: path(*)
            integer(c_int) :: status
        end function r2f_remove

        function r2f_path_kind(path) bind(C, name="r2f_path_kind") result(kind)
            import :: c_char, c_int
            character(kind=c_char), intent(in) :: path(*)
            integer(c_int) :: kind
        end function r2f_path_kind

        pure function c_strlen(str) bind(C, name="strlen") result(n)
            import :: c_ptr, c_size_t
            type(c_ptr), value :: str
            integer(c_size_t) :: n
        end function c_strlen
    end interface

contains

    !> OS_UNIX, OS_MACOS or OS_WINDOWS.
    pure integer function os()
        os = int(r2f_platform())
    end function os

    logical function path_exists(path)
        character(len=*), intent(in) :: path
        path_exists = r2f_path_kind(c_str(path)) /= PATH_NONE
    end function path_exists

    logical function is_directory(path)
        character(len=*), intent(in) :: path
        is_directory = r2f_path_kind(c_str(path)) == PATH_DIR
    end function is_directory

    !> Create a directory and any missing parents (like mkdir -p).
    logical function make_directory(path)
        character(len=*), intent(in) :: path
        make_directory = r2f_mkdir_p(c_str(path)) == 0_c_int
    end function make_directory

    !> Rename, replacing an existing target (also on Windows).
    logical function rename_file(from, to)
        character(len=*), intent(in) :: from, to
        rename_file = r2f_rename(c_str(from), c_str(to)) == 0_c_int
    end function rename_file

    logical function remove_file(path)
        character(len=*), intent(in) :: path
        remove_file = r2f_remove(c_str(path)) == 0_c_int
    end function remove_file

    !> const char* -> Fortran string ('' for a NULL pointer).
    function string_from_c_ptr(ptr) result(text)
        type(c_ptr), intent(in) :: ptr
        character(len=:), allocatable :: text
        character(kind=c_char), pointer :: chars(:)
        integer :: i, n

        if (.not. c_associated(ptr)) then
            text = ''
            return
        end if
        n = int(c_strlen(ptr))
        call c_f_pointer(ptr, chars, [n])
        allocate(character(len=n) :: text)
        do i = 1, n
            text(i:i) = chars(i)
        end do
    end function string_from_c_ptr

    ! ============================================================================================

    !> Fortran string -> NUL-terminated C string (length kept exactly).
    pure function c_str(value) result(c_value)
        character(len=*), intent(in) :: value
        character(kind=c_char) :: c_value(len(value) + 1)
        integer :: k

        do k = 1, len(value)
            c_value(k) = value(k:k)
        end do
        c_value(len(value) + 1) = c_null_char
    end function c_str

end module m_platform
