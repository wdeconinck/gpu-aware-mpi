! SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
! SPDX-License-Identifier: Apache-2.0

! roundtrip_omp.F90

program main
    use mpi
    use omp_lib, only: omp_get_num_devices
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

    if (omp_get_num_devices() < 1) then
        write(0,'(A,I0,A)') "Rank ", rank, ": No OpenMP target GPU available."
        call MPI_ABORT(MPI_COMM_WORLD, 1, ierr)
    endif

    ! Calculate dynamic ring neighbors for an arbitrary size
    next_rank = mod(rank + 1, size)
    prev_rank = mod(rank - 1 + size, size)

    ! Create the array space directly on the GPU device execution context
    !$omp target enter data map(alloc: h_buf)

    if (rank == 0) then
        ! Initialize host data
        do i = 1, count
            h_buf(i) = 200
        end do
        
        ! Push data down to the GPU device buffer
        !$omp target update to(h_buf)

        write(0,'(A,I0)') "Rank 0: Starting OpenMP ring. Sending data directly from GPU to Rank ", next_rank

        ! Force MPI to intercept and use the GPU pointer allocated for h_buf
        !$omp target data use_device_addr(h_buf)
        call MPI_SEND(h_buf, count, MPI_INTEGER, next_rank, 0, MPI_COMM_WORLD, ierr)
        call MPI_RECV(h_buf, count, MPI_INTEGER, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
        !$omp end target data

        write(0,'(A)') "Rank 0: OpenMP Ring complete! Token safely wrapped back to origin."

    else
        ! Intermediate nodes block-receive the GPU data stream first
        !$omp target data use_device_addr(h_buf)
        call MPI_RECV(h_buf, count, MPI_INTEGER, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE, ierr)
        !$omp end target data

        write(0,'(A,I0,A,I0)') "Rank ", rank, ": Data received directly into OpenMP target memory from Rank ", prev_rank

        ! Spot-check verification on the final link of the chain
        if (rank == size - 1) then
            ! Pull data back up from the device memory map to inspect it
            !$omp target update from(h_buf)
            write(0,'(A,I0,A,I0)') "Rank ", rank, " (Final Link): Verified element(1) = ", h_buf(1)
        endif

        write(0, '(A,I0,A,I0)') "Rank ", rank, ": Forwarding data directly from OpenMP target memory to Rank ", next_rank
        
        ! Forward the device-resident address downstream
        !$omp target data use_device_addr(h_buf)
        call MPI_SEND(h_buf, count, MPI_INTEGER, next_rank, 0, MPI_COMM_WORLD, ierr)
        !$omp end target data
    endif

    !$omp target update from(h_buf)
    if (any(h_buf /= 200)) then
        write(0,'(A,I0,A)') "Rank ", rank, ": Payload validation failed."
        call MPI_ABORT(MPI_COMM_WORLD, 1, ierr)
    endif
    call MPI_BARRIER(MPI_COMM_WORLD, ierr)
    if (rank == 0) write(0,'(A)') "GPU roundtrip validation passed."

    ! Wipe the allocated map cleanly off the GPU architecture
    !$omp target exit data map(delete: h_buf)
    call MPI_FINALIZE(ierr)
end program main
