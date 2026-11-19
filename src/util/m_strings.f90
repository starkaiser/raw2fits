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
!   Small string and path helpers shared by every other module: a growable
!   list of strings, number formatting (str), C strings, case folding and
!   path splitting / joining. On Windows both '\' and '/' separate paths.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_strings

    use, intrinsic :: iso_c_binding, only: c_char, c_null_char
    use, intrinsic :: iso_fortran_env, only: int32, int64, real64
    use :: m_platform, only: os, OS_WINDOWS

    implicit none (type, external)

    private

    !> Growable list of strings (amortised O(1) append). All strings live in
    !> one character buffer; entry i is chars(first(i):last(i)). This layout
    !> deliberately avoids deferred-length character components, which
    !> gfortran mis-handles in some -fcoarray=lib builds.
    type, public :: string_list_t
        integer :: n = 0
        integer :: used = 0
        character(len=1), allocatable :: chars(:)
        integer, allocatable :: first(:), last(:)
    contains
        procedure :: push => list_push
        procedure :: get => list_get
        procedure :: index_of => list_index_of
    end type string_list_t

    interface str
        module procedure str_int32, str_int64, str_real64
    end interface str

    public :: str, lower_ascii, strip, starts_with
    public :: to_c_string, from_c_chars
    public :: path_basename, path_dirname, path_stem, path_join

contains

    ! ---- string list ---------------------------------------------------------------------------

    subroutine list_push(self, text)
        class(string_list_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        character(len=1), allocatable :: chars_tmp(:)
        integer, allocatable :: int_tmp(:)
        integer :: i, need

        ! character storage
        need = self%used + len(text)
        if (.not. allocated(self%chars)) then
            allocate(self%chars(max(1024, need)))
        else if (need > size(self%chars)) then
            allocate(chars_tmp(max(2 * size(self%chars), need)))
            chars_tmp(1:self%used) = self%chars(1:self%used)
            self%chars = chars_tmp
        end if
        do i = 1, len(text)
            self%chars(self%used + i) = text(i:i)
        end do

        ! entry bounds
        if (.not. allocated(self%first)) then
            allocate(self%first(64), self%last(64))
        else if (self%n == size(self%first)) then
            allocate(int_tmp(2 * size(self%first)))
            int_tmp(1:self%n) = self%first(1:self%n)
            self%first = int_tmp
            int_tmp(1:self%n) = self%last(1:self%n)
            self%last = int_tmp
        end if
        self%n = self%n + 1
        self%first(self%n) = self%used + 1
        self%last(self%n) = need
        self%used = need
    end subroutine list_push

    function list_get(self, i) result(text)
        class(string_list_t), intent(in) :: self
        integer, intent(in) :: i
        character(len=:), allocatable :: text
        integer :: k, f

        f = self%first(i)
        allocate(character(len=self%last(i) - f + 1) :: text)
        do k = 1, len(text)
            text(k:k) = self%chars(f + k - 1)
        end do
    end function list_get

    !> Position of the first entry exactly equal to text (0 if absent).
    integer function list_index_of(self, text) result(pos)
        class(string_list_t), intent(in) :: self
        character(len=*), intent(in) :: text
        integer :: i, k, f
        logical :: equal

        pos = 0
        do i = 1, self%n
            if (self%last(i) - self%first(i) + 1 /= len(text)) cycle
            f = self%first(i)
            equal = .true.
            do k = 1, len(text)
                if (self%chars(f + k - 1) /= text(k:k)) then
                    equal = .false.
                    exit
                end if
            end do
            if (equal) then
                pos = i
                return
            end if
        end do
    end function list_index_of

    ! ---- numbers -------------------------------------------------------------------------------

    function str_int32(value) result(text)
        integer(int32), intent(in) :: value
        character(len=:), allocatable :: text
        character(len=16) :: buffer
        write(buffer, '(i0)') value
        text = trim(buffer)
    end function str_int32

    function str_int64(value) result(text)
        integer(int64), intent(in) :: value
        character(len=:), allocatable :: text
        character(len=24) :: buffer
        write(buffer, '(i0)') value
        text = trim(buffer)
    end function str_int64

    !> Compact real formatting: 6 significant digits, trailing zeros removed.
    function str_real64(value) result(text)
        real(real64), intent(in) :: value
        character(len=:), allocatable :: text
        character(len=32) :: buffer
        integer :: last

        write(buffer, '(g0.6)') value
        text = trim(adjustl(buffer))
        if (index(text, '.') > 0 .and. scan(text, 'eEdD') == 0) then
            last = len(text)
            do while (last > 1)
                if (text(last:last) /= '0') exit
                last = last - 1
            end do
            if (text(last:last) == '.') last = last - 1
            text = text(1:last)
        end if
    end function str_real64

    ! ---- text ----------------------------------------------------------------------------------

    pure function lower_ascii(value) result(lowered)
        character(len=*), intent(in) :: value
        character(len=len(value)) :: lowered
        integer :: i, c

        lowered = value
        do i = 1, len(value)
            c = iachar(value(i:i))
            if (c >= iachar('A') .and. c <= iachar('Z')) lowered(i:i) = achar(c + 32)
        end do
    end function lower_ascii

    !> Remove leading and trailing blanks, tabs, CR and LF.
    pure function strip(text) result(out)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: out
        integer :: first, last

        first = 1
        last = len(text)
        do while (first <= last)
            if (.not. is_space(text(first:first))) exit
            first = first + 1
        end do
        do while (last >= first)
            if (.not. is_space(text(last:last))) exit
            last = last - 1
        end do
        out = text(first:last)
    end function strip

    pure logical function is_space(c)
        character, intent(in) :: c
        is_space = c == ' ' .or. c == achar(9) .or. c == achar(10) .or. c == achar(13)
    end function is_space

    pure logical function starts_with(text, prefix)
        character(len=*), intent(in) :: text, prefix
        if (len(prefix) > len(text)) then
            starts_with = .false.
        else
            starts_with = text(1:len(prefix)) == prefix
        end if
    end function starts_with

    ! ---- C strings -----------------------------------------------------------------------------

    !> Fortran string -> NUL-terminated C character array (length kept exactly).
    pure function to_c_string(value) result(c_value)
        character(len=*), intent(in) :: value
        character(kind=c_char) :: c_value(len(value) + 1)
        integer :: k

        do k = 1, len(value)
            c_value(k) = value(k:k)
        end do
        c_value(len(value) + 1) = c_null_char
    end function to_c_string

    !> Fixed-size C char array (e.g. a struct member) -> trimmed Fortran string.
    function from_c_chars(chars) result(value)
        character(kind=c_char), intent(in) :: chars(:)
        character(len=:), allocatable :: value
        integer :: k, n

        n = size(chars)
        do k = 1, size(chars)
            if (chars(k) == c_null_char) then
                n = k - 1
                exit
            end if
        end do
        allocate(character(len=n) :: value)
        do k = 1, n
            value(k:k) = chars(k)
        end do
        value = trim(value)
    end function from_c_chars

    ! ---- paths ---------------------------------------------------------------------------------

    !> Characters that separate path components on this system.
    pure function separators() result(set)
        character(len=:), allocatable :: set
        if (os() == OS_WINDOWS) then
            set = '/' // achar(92)
        else
            set = '/'
        end if
    end function separators

    !> 'dir/IMG_0001.CR2' -> 'IMG_0001.CR2'
    pure function path_basename(path) result(name)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: name
        name = path(scan(path, separators(), back=.true.) + 1:)
    end function path_basename

    !> 'dir/IMG_0001.CR2' -> 'dir';  'IMG_0001.CR2' -> '';  '/x' -> '/'
    pure function path_dirname(path) result(dir)
        character(len=*), intent(in) :: path
        character(len=:), allocatable :: dir
        integer :: slash

        slash = scan(path, separators(), back=.true.)
        if (slash == 0) then
            dir = ''
        else if (slash == 1) then
            dir = path(1:1)
        else
            dir = path(1:slash - 1)
        end if
    end function path_dirname

    !> 'IMG_0001.CR2' -> 'IMG_0001';  '.hidden' stays unchanged.
    pure function path_stem(name) result(stem)
        character(len=*), intent(in) :: name
        character(len=:), allocatable :: stem
        integer :: dot

        dot = index(name, '.', back=.true.)
        if (dot > 1) then
            stem = name(1:dot - 1)
        else
            stem = name
        end if
    end function path_stem

    pure function path_join(dir, name) result(path)
        character(len=*), intent(in) :: dir, name
        character(len=:), allocatable :: path

        if (len(dir) == 0) then
            path = name
        else if (scan(dir(len(dir):len(dir)), separators()) > 0) then
            path = dir // name
        else
            path = dir // '/' // name
        end if
    end function path_join

end module m_strings
