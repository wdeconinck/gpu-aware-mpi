! SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
! SPDX-License-Identifier: Apache-2.0

! roundtrip_acc.F90

program main
    use mpi
    use openacc
    implicit none

    integer :: rank, size, ierr, i
    integer :: next_rank, prev_rank
    integer, parameter :: count = 10
    integer, target :: h_buf(count)

    call MPI_INIT(ierr)
    call MPI_COMM_RANK(MPI_COMM_WORLD, rank, ierr)
    call MPI_COMM_SIZE(MPI_COMM_WORLD, size, ierr)

    if (size < 2) then
        if (rank == 0) write(0,'(A)') "This program requires at least 2 MPI ranks."
        call MPI_ABORT(MPI_COMM_WORLD, 1, ierr)
    endif

    if (acc_get_num_devices(acc_device_nvidia) < 1) then
        write(0,'(A,I0,A)') "Rank ", rank, ": No NVIDIA GPU available."
        call MPI_ABORT(MPI_COMM_WORLD, 1, ierr)
    endif
    call acc_set_device_type(acc_device_nvidia)

    ! Calculate dynamic ring neighbors for an arbitrary size
    next_rank = mod(rank + 1, size)
    prev_rank = mod(rank - 1 + size, size)

    ! Create the array space on the GPU device mapping to h_buf
    !$acc enter data create(h_buf)

    if (rank == 0) then
        ! Initialize host data
        do i = 1, count
            h_buf(i) = 100
        end do
        ! Push data down to the GPU device buffer
        !$acc update device(h_buf)

        write(0,'(A,I0)') "Rank 0: Starting ring. Sending data directly from OpenACC to Rank ", next_rank

        ! Ring Start: Rank 0 sends first, then blocks for the final wrap-around receive
        !$acc host_data use_device(h_buf)
        call MPI_SEND(h_buf, count, MPI_INTEGER, next_rank, 0, MPI_COMM_WORLD, ierr)
        call MPI_RECV(h_buf, count, MPI_INTEGER, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
        !$acc end host_data

        write(0,'(A)')  "Rank 0: Ring complete! Token safely wrapped around back to origin."

    else
        ! Intermediate nodes block-receive the GPU data stream first
        !$acc host_data use_device(h_buf)
        call MPI_RECV(h_buf, count, MPI_INTEGER, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
        !$acc end host_data

        write(0,'(A,I0,A,I0)') "Rank ", rank, ": Data received directly into OpenACC from Rank ", prev_rank

        ! Spot-check verification on the final link of the chain
        if (rank == size - 1) then
            ! Bring the data up to the CPU host to inspect it
            !$acc update self(h_buf)
            write(0,'(A,I0,A,I0)') "Rank ", rank, " (Final Link): Verified element(1) = ", h_buf(1)
        endif

        write(0,'(A,I0,A,I0)') "Rank ", rank, ": Forwarding data directly from OpenACC to Rank ", next_rank
        
        ! Forward the GPU address downstream to the next link
        !$acc host_data use_device(h_buf)
        call MPI_SEND(h_buf, count, MPI_INTEGER, next_rank, 0, MPI_COMM_WORLD, ierr)
        !$acc end host_data
    endif

    !$acc update self(h_buf)
    if (any(h_buf /= 100)) then
        write(0,'(A,I0,A)') "Rank ", rank, ": Payload validation failed."
        call MPI_ABORT(MPI_COMM_WORLD, 1, ierr)
    endif
    call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    if (rank == 0) write(0,'(A)') "GPU roundtrip validation passed."

    ! Clean up GPU array memory footprints cleanly
    !$acc exit data delete(h_buf)
    call MPI_FINALIZE(ierr)
end program main
