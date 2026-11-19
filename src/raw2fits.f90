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
!   Main program. Parses the command line, plans the jobs (one per RAW file)
!   and hands them to m_workers, which is either
!
!     m_workers_threads.f90   OpenMP threads, one process  (default, releases)
!     m_workers_coarray.f90   coarray images                (make BACKEND=coarray)
!
!       raw2fits [OPTION]... RAW-FILE...                   (threads: -j N)
!       cafrun -n 4 raw2fits-caf [OPTION]... RAW-FILE...    (coarray build)
!
!   Every exit path leaves the main block, so all workers meet again in
!   workers_finish() before the program ends.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

program raw2fits

    use, intrinsic :: iso_fortran_env, only: int64, real64, output_unit, error_unit
    use :: m_strings, only: string_list_t, str
    use :: m_options, only: options_t, parse_command_line, print_usage, &
                            PARSE_HELP, PARSE_VERSION, PARSE_ERROR
    use :: m_output, only: output_extension
    use :: m_platform, only: make_directory
    use :: m_raw, only: libraw_version_string
    use :: m_jobs, only: job_list_t, run_stats_t, plan_jobs, job_count
    use :: m_workers, only: workers_run, workers_is_primary, workers_any, workers_finish, &
                            workers_describe
    use :: m_log, only: log_set_level, log_error
    use :: m_config, only: APP_NAME, APP_VERSION, APP_BACKEND

    implicit none (type, external)

    type(options_t) :: opts
    type(string_list_t) :: names
    type(job_list_t) :: jobs
    type(run_stats_t) :: stats
    character(len=:), allocatable :: msg
    integer :: action, exit_code
    integer(int64) :: t_start, t_end, t_rate
    logical :: ok, primary

    primary = workers_is_primary()
    call system_clock(t_start, t_rate)
    exit_code = 0

    main: block
        ! ---- command line ------------------------------------------------------------------------
        if (command_argument_count() == 0) then
            if (primary) call print_usage()
            exit_code = 2
            exit main
        end if
        call parse_command_line(opts, names, action, msg)
        select case (action)
        case (PARSE_HELP)
            if (primary) call print_usage()
            exit main
        case (PARSE_VERSION)
            if (primary) call print_version()
            exit main
        case (PARSE_ERROR)
            if (primary) then
                write(error_unit, '(a)') APP_NAME//': '//msg
                write(error_unit, '(a)') "Try '"//APP_NAME//" --help' for more information."
            end if
            exit_code = 2
            exit main
        end select
        call log_set_level(opts%verbosity)

        ! ---- jobs: identical on every worker -----------------------------------------------------
        call plan_jobs(names, opts, primary, jobs, ok)
        if (.not. ok) then
            exit_code = 2
            exit main
        end if
        if (opts%dry_run) then
            if (primary) call print_plan()
            exit main
        end if

        ! The primary worker creates the output directory; the others wait for the result.
        if (len_trim(opts%outdir) > 0) then
            ok = .true.
            if (primary) then
                ok = make_directory(trim(opts%outdir))
                if (.not. ok) call log_error('cannot create output directory '//trim(opts%outdir))
            end if
            if (workers_any(.not. ok)) then
                exit_code = 1
                exit main
            end if
        end if

        ! ---- conversion --------------------------------------------------------------------------
        call workers_run(jobs, stats)

        if (primary) then
            call system_clock(t_end)
            if (opts%verbosity >= 1 .or. stats%failed + stats%unsupported > 0) call print_summary()
        end if
        if (stats%failed + stats%unsupported > 0) exit_code = 1
    end block main

    call workers_finish(exit_code)

contains

    subroutine print_version()
        write(output_unit, '(a)') APP_NAME//' '//APP_VERSION//' ('//APP_BACKEND//' backend)'
        write(output_unit, '(a)') 'LibRaw '//libraw_version_string()
        write(output_unit, '(a)') 'Parallel: '//workers_describe()
    end subroutine print_version

    subroutine print_plan()
        integer :: k
        character(len=:), allocatable :: ext

        ext = output_extension(opts)
        do k = 1, job_count(jobs)
            write(output_unit, '(a)') jobs%inputs%get(k)//' -> '//jobs%stems%get(k)//'.'//ext
        end do
        write(output_unit, '(a)') str(job_count(jobs))//' file(s) would be converted'// &
            ' (multi-channel files get .chN before the extension).'
    end subroutine print_plan

    subroutine print_summary()
        real(real64) :: seconds
        character(len=16) :: secs
        character(len=:), allocatable :: unit_name

        seconds = real(t_end - t_start, real64) / real(max(t_rate, 1_int64), real64)
        write(secs, '(f0.1)') seconds
        if (secs(1:1) == '.') secs = '0'//secs
        unit_name = merge(' images ', ' threads', APP_BACKEND == 'coarray')
        if (stats%workers == 1) unit_name = merge(' image ', ' thread', APP_BACKEND == 'coarray')
        write(output_unit, '(a)') 'Done: '//str(stats%converted)//' converted, '// &
            str(stats%failed)//' failed, '//str(stats%unsupported)//' unsupported, '// &
            str(stats%skipped)//' skipped; '//str(stats%workers)//trim(unit_name)//', '// &
            trim(secs)//' s'
    end subroutine print_summary

end program raw2fits
