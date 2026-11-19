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
!   Worker backend 2 of 2: coarray images (make BACKEND=coarray, builds
!   raw2fits-caf; run it with cafrun -n N or raw2fits-par -j N, N >= 2).
!
!   Every image parses the same command line and builds the same job list,
!   so no file names have to be sent around. The files are then shared:
!
!     --schedule=static   image k converts files k, k+N, k+2N, ... (default)
!     --schedule=dynamic  every image atomically takes the next unconverted
!                         file from a counter on image 1 (atomic_fetch_add)
!
!   The totals are summed with co_sum. workers_finish() synchronises all
!   images before any of them exits: mpirun ends the whole job as soon as
!   one image stops, which could cut off image 1's buffered output. A plain
!   STOP makes OpenCoarrays call MPI_Abort, so success falls through to END
!   PROGRAM instead.
!
!   With Debian/Ubuntu's OpenMPI 4.1 a coarray program aborts in
!   MPI_Win_create when started as a single image (OSC pt2pt does not
!   support MPI_THREAD_MULTIPLE), hence N >= 2.
!
!   The public interface is identical to m_workers_threads.f90.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_workers

    use, intrinsic :: iso_fortran_env, only: atomic_int_kind, output_unit, error_unit
    use :: m_jobs, only: job_list_t, run_stats_t, job_count, process_job, count_result
    use :: m_options, only: SCHED_DYNAMIC
    use :: m_strings, only: str
    use :: m_log, only: log_set_tag, log_detail, log_warn

    implicit none (type, external)

    private

    ! ---- coarrays ------------------------------------------------------------------------------
    integer(atomic_int_kind), save :: next_job[*]     !< dynamic schedule: jobs taken (image 1)

    public :: workers_run, workers_is_primary, workers_any, workers_finish, workers_describe

contains

    !> Convert this image's share of the jobs; stats are the totals of all images.
    subroutine workers_run(jobs, stats)
        type(job_list_t), intent(in) :: jobs
        type(run_stats_t), intent(out) :: stats
        integer(atomic_int_kind) :: taken
        integer :: me, n, i, status

        me = this_image()
        n = job_count(jobs)
        if (num_images() > 1) call log_set_tag('['//str(me)//'/'//str(num_images())//']')
        if (jobs%opts%jobs > 1 .and. me == 1) &
            call log_warn('--jobs is ignored by the coarray build; use cafrun -n N / raw2fits-par -j N')

        stats = run_stats_t()
        if (jobs%opts%schedule == SCHED_DYNAMIC) then
            if (me == 1) call atomic_define(next_job, 0_atomic_int_kind)
            sync all
            do
                call atomic_fetch_add(next_job[1], 1_atomic_int_kind, taken)
                i = int(taken) + 1
                if (i > n) exit
                call process_job(jobs, i, status)
                call count_result(stats, status)
            end do
        else
            call log_detail('assigned '//str(static_share(n, me, num_images()))//' of '// &
                            str(n)//' file(s)')
            do i = me, n, num_images()
                call process_job(jobs, i, status)
                call count_result(stats, status)
            end do
        end if

        call co_sum(stats%converted)
        call co_sum(stats%failed)
        call co_sum(stats%unsupported)
        call co_sum(stats%skipped)
        stats%workers = num_images()
        call log_set_tag('')
    end subroutine workers_run

    !> Only image 1 prints usage, the plan and the summary.
    logical function workers_is_primary()
        workers_is_primary = this_image() == 1
    end function workers_is_primary

    !> Collective: .true. on every image if flag is .true. on any image.
    logical function workers_any(flag)
        logical, intent(in) :: flag
        integer :: value
        value = merge(1, 0, flag)
        call co_max(value)
        workers_any = value /= 0
    end function workers_any

    !> Collective common exit: flush, wait for every image, then stop with
    !> exit_code if it is not 0 (success returns and reaches END PROGRAM).
    subroutine workers_finish(exit_code)
        integer, intent(in) :: exit_code
        flush(output_unit)
        flush(error_unit)
        sync all
        if (exit_code /= 0) stop exit_code, quiet=.true.
    end subroutine workers_finish

    !> For --version.
    function workers_describe() result(text)
        character(len=:), allocatable :: text
        text = 'coarray images ('//str(num_images())//' running; start with cafrun -n N, N >= 2)'
    end function workers_describe

    ! ============================================================================================

    !> Number of files image `image` gets under the static schedule.
    pure integer function static_share(task_count, image, images) result(n)
        integer, intent(in) :: task_count, image, images
        if (image > task_count) then
            n = 0
        else
            n = (task_count - image) / images + 1
        end if
    end function static_share

end module m_workers
