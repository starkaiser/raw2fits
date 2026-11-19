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
!   What a conversion job is, independent of how it is executed. The job
!   list holds every input file with its output name; both worker backends
!   (OpenMP threads in m_workers_threads.f90, coarray images in
!   m_workers_coarray.f90) call process_job() for their files and add up the
!   results in a run_stats_t.
!
!   One job: decode the RAW file with LibRaw -> optional autoscale / gamma
!   -> select the sensor area -> write one output file per raw channel.
!   Jobs share nothing but the read-only job list, so any number of them
!   can run at the same time (each one has its own LibRaw handle).
!
! WRITTEN BY :
!   Sorin Cătălin Păștiță, November 2026
!
! ==================================================================================================

module m_jobs

    use :: m_strings, only: string_list_t, str
    use :: m_options, only: options_t
    use :: m_frame, only: frame_t, region_t, CFA_BAYER, CFA_XTRANS, cfa_pattern
    use :: m_raw, only: load_raw, LOAD_OK, LOAD_UNSUPPORTED
    use :: m_pixel_ops, only: select_region, autoscale, apply_gamma
    use :: m_output, only: output_stem, output_path, output_extension, outputs_exist, write_output
    use :: m_platform, only: path_exists, is_directory
    use :: m_log, only: log_info, log_detail, log_warn, log_error

    implicit none (type, external)

    private

    integer, parameter, public :: JOB_OK          = 0
    integer, parameter, public :: JOB_FAILED      = 1
    integer, parameter, public :: JOB_UNSUPPORTED = 2   !< LibRaw has no raw buffer we can use
    integer, parameter, public :: JOB_SKIPPED     = 3   !< output exists and --skip-existing

    !> Every file to convert, with its output name (without channel / extension).
    type, public :: job_list_t
        type(options_t) :: opts
        type(string_list_t) :: inputs
        type(string_list_t) :: stems
    end type job_list_t

    !> Results of a run; workers is the number of threads / images that ran.
    type, public :: run_stats_t
        integer :: converted   = 0
        integer :: failed      = 0
        integer :: unsupported = 0
        integer :: skipped     = 0
        integer :: workers     = 1
    end type run_stats_t

    public :: plan_jobs, job_count, process_job, count_result

contains

    !> Build the job list from the input names: repeated names are dropped,
    !> and the run is refused (ok = .false.) if two inputs would write the
    !> same output file. Messages only when report (one worker reports).
    subroutine plan_jobs(names, opts, report, jobs, ok)
        type(string_list_t), intent(in) :: names
        type(options_t), intent(in) :: opts
        logical, intent(in) :: report
        type(job_list_t), intent(out) :: jobs
        logical, intent(out) :: ok
        integer :: i, first, duplicates

        jobs%opts = opts
        duplicates = 0
        do i = 1, names%n
            if (jobs%inputs%index_of(names%get(i)) == 0) then
                call jobs%inputs%push(names%get(i))
            else
                duplicates = duplicates + 1
            end if
        end do
        if (duplicates > 0 .and. report) &
            call log_warn(str(duplicates)//' repeated input file name(s) ignored')

        do i = 1, jobs%inputs%n
            call jobs%stems%push(output_stem(jobs%inputs%get(i), opts))
        end do

        ok = .true.
        do i = 1, jobs%stems%n
            first = jobs%stems%index_of(jobs%stems%get(i))
            if (first /= i) then
                ok = .false.
                if (report) call log_error(jobs%inputs%get(i)//' and '//jobs%inputs%get(first)// &
                    ' would write the same output '//jobs%stems%get(i)//'.'//output_extension(opts)// &
                    ' (use --keep-ext)')
            end if
        end do
    end subroutine plan_jobs

    integer function job_count(jobs)
        type(job_list_t), intent(in) :: jobs
        job_count = jobs%inputs%n
    end function job_count

    !> Convert file number i of the list; status is one of the JOB_* codes.
    subroutine process_job(jobs, i, status)
        type(job_list_t), intent(in) :: jobs
        integer, intent(in) :: i
        integer, intent(out) :: status
        call convert_file(jobs%inputs%get(i), jobs%stems%get(i), jobs%opts, status)
    end subroutine process_job

    !> Add one job result to the counters.
    subroutine count_result(stats, status)
        type(run_stats_t), intent(inout) :: stats
        integer, intent(in) :: status

        select case (status)
        case (JOB_OK)
            stats%converted = stats%converted + 1
        case (JOB_UNSUPPORTED)
            stats%unsupported = stats%unsupported + 1
        case (JOB_SKIPPED)
            stats%skipped = stats%skipped + 1
        case default
            stats%failed = stats%failed + 1
        end select
    end subroutine count_result

    ! ============================================================================================

    !> Convert input; the output files are named from stem (see m_output).
    subroutine convert_file(input, stem, opts, status)
        character(len=*), intent(in) :: input, stem
        type(options_t), intent(in) :: opts
        integer, intent(out) :: status
        type(frame_t) :: frame
        type(region_t) :: region
        character(len=:), allocatable :: msg, ext, path, written
        integer :: load_status, ch, factor, peak
        logical :: ok, fell_back

        ext = output_extension(opts)
        if (opts%skip_existing) then
            if (outputs_exist(stem, ext)) then
                call log_info(input//': output exists, skipped')
                status = JOB_SKIPPED
                return
            end if
        end if
        if (.not. path_exists(input)) then
            call log_error(input//': no such file')
            status = JOB_FAILED
            return
        end if
        if (is_directory(input)) then
            call log_error(input//': is a directory')
            status = JOB_FAILED
            return
        end if

        ! ---- decode
        call load_raw(input, opts%shot, frame, load_status, msg)
        if (load_status /= LOAD_OK) then
            call log_error(input//': '//msg)
            if (load_status == LOAD_UNSUPPORTED) then
                status = JOB_UNSUPPORTED
            else
                status = JOB_FAILED
            end if
            return
        end if
        call log_detail(input//': '//describe(frame))

        ! ---- optional pixel processing
        if (opts%autoscale) then
            call autoscale(frame, factor, peak)
            if (factor > 1) then
                call log_detail(input//': autoscaled x'//str(factor)//' (peak '//str(peak)//')')
            else
                call log_detail(input//': autoscale not needed (peak '//str(peak)//')')
            end if
        end if
        if (opts%gamma) then
            call apply_gamma(frame)
            call log_detail(input//': gamma 2.2 applied')
        end if

        ! ---- area
        call select_region(frame, opts%area, region, fell_back, ok)
        if (.not. ok) then
            call log_error(input//': invalid sensor geometry for the requested area')
            status = JOB_FAILED
            return
        end if
        if (fell_back) call log_detail(input//': no usable default crop, using the active area')

        ! ---- write one file per channel
        status = JOB_OK
        do ch = 1, frame%channels
            path = output_path(stem, ch, frame%channels, ext)
            call write_output(frame, region, ch, opts%format, path, ok, msg)
            if (.not. ok) then
                call log_error(path//': '//msg)
                status = JOB_FAILED
            end if
        end do

        if (status == JOB_OK) then
            if (frame%channels > 1) then
                written = stem//'.ch{1..'//str(frame%channels)//'}.'//ext
            else
                written = path
            end if
            call log_info(input//' -> '//written//' ['//str(region%width)//'x'// &
                          str(region%height)//' '//trim(region%name)//pattern_note(frame, region)//']')
        end if
    end subroutine convert_file

    function pattern_note(frame, region) result(text)
        type(frame_t), intent(in) :: frame
        type(region_t), intent(in) :: region
        character(len=:), allocatable :: text

        select case (frame%cfa)
        case (CFA_BAYER)
            text = ' '//cfa_pattern(frame, region, 2, 2)
        case (CFA_XTRANS)
            text = ' X-Trans'
        case default
            text = ''
        end select
    end function pattern_note

    function describe(frame) result(text)
        type(frame_t), intent(in) :: frame
        character(len=:), allocatable :: text

        text = 'raw '//str(frame%raw_width)//'x'//str(frame%raw_height)// &
               ', active '//str(frame%active_width)//'x'//str(frame%active_height)// &
               ' at ('//str(frame%left_margin)//','//str(frame%top_margin)//')'
        if (frame%has_crop) then
            text = text//', crop '//str(frame%crop_width)//'x'//str(frame%crop_height)// &
                   ' at ('//str(frame%crop_left)//','//str(frame%crop_top)//')'
        end if
        text = text//', '//str(frame%channels)//' channel(s)'
        if (frame%from_float) text = text//', float data scaled to 16 bit'
        text = text//', ISO '//str(nint(frame%meta%iso))//', '//str(frame%meta%exposure)//' s'
    end function describe

end module m_jobs
