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
!   Worker backend 1 of 2: OpenMP threads in one process (make BACKEND=threads,
!   the default and what the release builds use).
!
!   The job list is shared read-only; each thread takes the next unconverted
!   file (schedule dynamic, 1), so a slow file never holds up the others.
!   Every thread counts its own results and adds them to the totals once,
!   inside a named critical section, at the end.
!
!   Thread count: --jobs N, else $OMP_NUM_THREADS or the number of cores;
!   never more threads than files. The public interface is identical to
!   m_workers_coarray.f90.
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_workers

    use, intrinsic :: iso_fortran_env, only: output_unit, error_unit
    use :: omp_lib, only: omp_get_max_threads, omp_get_thread_num, omp_get_num_threads, &
                          omp_set_dynamic
    use :: m_jobs, only: job_list_t, run_stats_t, job_count, process_job, count_result
    use :: m_strings, only: str
    use :: m_log, only: log_set_tag, log_detail

    implicit none (type, external)

    private

    public :: workers_run, workers_is_primary, workers_any, workers_finish, workers_describe

contains

    !> Convert every job of the list; stats are the totals of all threads.
    subroutine workers_run(jobs, stats)
        type(job_list_t), intent(in) :: jobs
        type(run_stats_t), intent(out) :: stats
        type(run_stats_t) :: mine
        integer :: wanted, i, status

        wanted = thread_count(jobs%opts%jobs, job_count(jobs))
        if (wanted > 1) call log_detail('converting with '//str(wanted)//' OpenMP threads')
        stats = run_stats_t(workers=wanted)

        call omp_set_dynamic(.false.)
        !$omp parallel num_threads(wanted) default(shared) private(mine, i, status)
        mine = run_stats_t()
        if (omp_get_num_threads() > 1) &
            call log_set_tag('['//str(omp_get_thread_num() + 1)//'/'//str(omp_get_num_threads())//']')

        !$omp do schedule(dynamic, 1)
        do i = 1, job_count(jobs)
            call process_job(jobs, i, status)
            call count_result(mine, status)
        end do
        !$omp end do

        !$omp critical (r2f_stats)
        stats%converted   = stats%converted   + mine%converted
        stats%failed      = stats%failed      + mine%failed
        stats%unsupported = stats%unsupported + mine%unsupported
        stats%skipped     = stats%skipped     + mine%skipped
        !$omp end critical (r2f_stats)

        !$omp single
        ! The runtime may grant fewer threads than asked for.
        stats%workers = omp_get_num_threads()
        !$omp end single
        call log_set_tag('')
        !$omp end parallel
    end subroutine workers_run

    !> Only the primary worker prints usage, the plan and the summary.
    logical function workers_is_primary()
        workers_is_primary = .true.
    end function workers_is_primary

    !> Collective OR of flag over all workers (one process: flag itself).
    logical function workers_any(flag)
        logical, intent(in) :: flag
        workers_any = flag
    end function workers_any

    !> Common exit: flush the output, then stop with exit_code if it is not 0.
    subroutine workers_finish(exit_code)
        integer, intent(in) :: exit_code
        flush(output_unit)
        flush(error_unit)
        if (exit_code /= 0) stop exit_code, quiet=.true.
    end subroutine workers_finish

    !> For --version.
    function workers_describe() result(text)
        character(len=:), allocatable :: text
        text = 'OpenMP threads ('//str(omp_get_max_threads())//' available; choose with -j N)'
    end function workers_describe

    ! ============================================================================================

    !> --jobs if > 0, else OMP_NUM_THREADS or the number of cores; at most one
    !> thread per file.
    integer function thread_count(jobs, task_count) result(n)
        integer, intent(in) :: jobs, task_count
        n = omp_get_max_threads()
        if (jobs > 0) n = jobs
        n = max(1, min(n, task_count))
    end function thread_count

end module m_workers
