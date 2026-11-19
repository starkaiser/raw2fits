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
!   Builder for FITS headers made of 80-character cards (any number of cards;
!   the header is padded to whole 2880-byte blocks).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_fits_header

    use, intrinsic :: iso_fortran_env, only: real64
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite

    implicit none (type, external)

    private

    public :: fits_header_t, FITS_BLOCK, FITS_CARD

    integer, parameter :: FITS_BLOCK = 2880
    integer, parameter :: FITS_CARD = 80
    !> Longest string value that fits a card: 80 - 10 ('KEY     = ') - 2 quotes.
    integer, parameter :: MAX_STRING = 68

    type :: fits_header_t
        character(len=FITS_CARD), allocatable :: cards(:)
        integer :: n = 0
    contains
        procedure :: add_logical => hdr_add_logical
        procedure :: add_int => hdr_add_int
        procedure :: add_real => hdr_add_real
        procedure :: add_string => hdr_add_string
        procedure :: add_comment => hdr_add_comment
        procedure :: add_history => hdr_add_history
        procedure :: finish => hdr_finish
        procedure :: as_block => hdr_as_block
        procedure :: as_text => hdr_as_text
        procedure :: card => hdr_card
    end type fits_header_t

contains

    subroutine hdr_append(self, card)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: card
        character(len=FITS_CARD), allocatable :: grown(:)

        if (.not. allocated(self%cards)) allocate(self%cards(36))
        if (self%n == size(self%cards)) then
            allocate(grown(2 * size(self%cards)))
            grown(1:self%n) = self%cards(1:self%n)
            self%cards = grown
        end if
        self%n = self%n + 1
        self%cards(self%n) = card
    end subroutine hdr_append

    !> 'KEY     = value / comment'; numbers are right-justified to column 30.
    function value_card(key, value, comment) result(card)
        character(len=*), intent(in) :: key, value, comment
        character(len=FITS_CARD) :: card
        integer :: pos

        card = ' '
        card(1:8) = key
        card(9:10) = '= '
        card(11:) = value
        pos = 11 + len(value)
        if (len_trim(comment) > 0 .and. pos + 3 <= FITS_CARD) card(pos:) = ' / ' // comment
    end function value_card

    pure function opt_text(text) result(out)
        character(len=*), intent(in), optional :: text
        character(len=:), allocatable :: out
        if (present(text)) then
            out = text
        else
            out = ''
        end if
    end function opt_text

    !> Quoted FITS string: quotes doubled, non-printable characters replaced,
    !> padded to at least 8 characters, truncated to fit one card.
    function fits_string(text) result(value)
        character(len=*), intent(in) :: text
        character(len=:), allocatable :: value, body
        character(len=2) :: piece
        integer :: i, c, np

        body = ''
        do i = 1, len_trim(text)
            c = iachar(text(i:i))
            if (text(i:i) == "'") then
                piece = "''"
                np = 2
            else if (c < 32 .or. c > 126) then
                piece = '?'
                np = 1
            else
                piece = text(i:i)
                np = 1
            end if
            if (len(body) + np > MAX_STRING) exit
            body = body // piece(1:np)
        end do
        if (len(body) < 8) body = body // repeat(' ', 8 - len(body))
        value = "'" // body // "'"
    end function fits_string

    subroutine hdr_add_logical(self, key, value, comment)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: key
        logical, intent(in) :: value
        character(len=*), intent(in), optional :: comment

        call hdr_append(self, value_card(key, repeat(' ', 19) // merge('T', 'F', value), &
                                                                          opt_text(comment)))
    end subroutine hdr_add_logical

    subroutine hdr_add_int(self, key, value, comment)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: key
        integer, intent(in) :: value
        character(len=*), intent(in), optional :: comment
        character(len=20) :: field

        write(field, '(i20)') value
        call hdr_append(self, value_card(key, field, opt_text(comment)))
    end subroutine hdr_add_int

    !> Real value; fmt is a Fortran edit descriptor producing <= 20 characters
    !> (default g20.10).  Non-finite values are silently skipped.
    subroutine hdr_add_real(self, key, value, comment, fmt)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: key
        real(real64), intent(in) :: value
        character(len=*), intent(in), optional :: comment, fmt
        character(len=20) :: field

        if (.not. ieee_is_finite(value)) return
        if (present(fmt)) then
            write(field, fmt) value
        else
            write(field, '(g20.10)') value
        end if
        call hdr_append(self, value_card(key, adjustr(field), opt_text(comment)))
    end subroutine hdr_add_real

    subroutine hdr_add_string(self, key, value, comment)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: key, value
        character(len=*), intent(in), optional :: comment

        call hdr_append(self, value_card(key, fits_string(value), opt_text(comment)))
    end subroutine hdr_add_string

    subroutine hdr_add_comment(self, text)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        call hdr_append(self, 'COMMENT ' // text)
    end subroutine hdr_add_comment

    subroutine hdr_add_history(self, text)
        class(fits_header_t), intent(inout) :: self
        character(len=*), intent(in) :: text
        call hdr_append(self, 'HISTORY ' // text)
    end subroutine hdr_add_history

    subroutine hdr_finish(self)
        class(fits_header_t), intent(inout) :: self
        call hdr_append(self, 'END')
    end subroutine hdr_finish

    !> The header as written to a FITS file (blank-padded to 2880 bytes).
    function hdr_as_block(self) result(bytes)
        class(fits_header_t), intent(in) :: self
        character(len=:), allocatable :: bytes
        integer :: i, total

        total = ((self%n * FITS_CARD + FITS_BLOCK - 1) / FITS_BLOCK) * FITS_BLOCK
        bytes = repeat(' ', max(total, FITS_BLOCK))
        do i = 1, self%n
            bytes((i - 1) * FITS_CARD + 1:i * FITS_CARD) = self%cards(i)
        end do
    end function hdr_as_block

    !> The cards as text, trailing blanks removed, one card per line.
    function hdr_as_text(self) result(text)
        class(fits_header_t), intent(in) :: self
        character(len=:), allocatable :: text
        integer :: i

        text = ''
        do i = 1, self%n
            text = text // trim(self%cards(i)) // new_line('a')
        end do
    end function hdr_as_text

    !> First card with the given keyword ('' if absent).
    function hdr_card(self, key) result(card)
        class(fits_header_t), intent(in) :: self
        character(len=*), intent(in) :: key
        character(len=:), allocatable :: card
        character(len=8) :: probe
        integer :: i

        probe = key
        card = ''
        do i = 1, self%n
            if (self%cards(i)(1:8) == probe) then
                card = self%cards(i)
                return
            end if
        end do
    end function hdr_card

end module m_fits_header
