// SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
// SPDX-License-Identifier: Apache-2.0

// roundtrip_cuda.cu

#include <mpi.h>
#include <cuda_runtime.h>
#include <iostream>
#include <vector>

int main(int argc, char** argv) {
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (size < 2) {
        if (rank == 0) std::cerr << "This program requires at least 2 MPI ranks.\n";
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    auto check_cuda = [rank](cudaError_t status) {
        if (status != cudaSuccess) {
            std::cerr << "Rank " << rank << ": CUDA error: " << cudaGetErrorString(status) << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
    };

    // Bind each local MPI rank to a specific GPU (basic 1-to-1 mapping)
    int num_devices = 0;
    check_cuda(cudaGetDeviceCount(&num_devices));
    if (num_devices == 0) {
        std::cerr << "Rank " << rank << ": No CUDA GPU available." << std::endl;
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    check_cuda(cudaSetDevice(rank % num_devices));

    const int count = 10;
    const int size_bytes = count * sizeof(int);
    int *d_buf = nullptr;

    // Allocate buffer directly on the GPU
    check_cuda(cudaMalloc(&d_buf, size_bytes));

    // Calculate ring neighbors dynamically for an arbitrary size
    int next_rank = (rank + 1) % size;
    int prev_rank = (rank - 1 + size) % size;

    // Initialize the token payload on Rank 0
    if (rank == 0) {
        std::vector<int> h_buf(count, 42);
        // Copy initial data to GPU device memory
        check_cuda(cudaMemcpy(d_buf, h_buf.data(), size_bytes, cudaMemcpyHostToDevice));
        
        std::cout << "Rank 0: Starting ring. Sending data directly from GPU to Rank " << next_rank << "..." << std::endl;
        
        // Ring Start: Rank 0 sends first, then waits for the wrap-around message at the end
        MPI_Send(d_buf, count, MPI_INT, next_rank, 0, MPI_COMM_WORLD);
        MPI_Recv(d_buf, count, MPI_INT, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        
        std::cout << "Rank 0: Ring complete! Token safely wrapped around and received back directly into GPU." << std::endl;
    } 
    else {
        // All other intermediate ranks block-receive first, then pass the GPU pointer forward
        MPI_Recv(d_buf, count, MPI_INT, prev_rank, 0, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        
        std::cout << "Rank " << rank << ": Data received directly into GPU from Rank " << prev_rank << "!" << std::endl;

        // Spot-check validation on intermediate ranks to confirm data integrity
        if (rank == size - 1) {
            std::vector<int> h_buf(count, 0);
            check_cuda(cudaMemcpy(h_buf.data(), d_buf, size_bytes, cudaMemcpyDeviceToHost));
            std::cout << "Rank " << rank << " (Final Link): Verified element[0] = " << h_buf[0] << std::endl;
        }

        std::cout << "Rank " << rank << ": Forwarding data directly from GPU to Rank " << next_rank << "..." << std::endl;
        MPI_Send(d_buf, count, MPI_INT, next_rank, 0, MPI_COMM_WORLD);
    }

    std::vector<int> received(count, 0);
    check_cuda(cudaMemcpy(received.data(), d_buf, size_bytes, cudaMemcpyDeviceToHost));
    for (int value : received) {
        if (value != 42) {
            std::cerr << "Rank " << rank << ": Payload validation failed." << std::endl;
            MPI_Abort(MPI_COMM_WORLD, 1);
        }
    }
    MPI_Barrier(MPI_COMM_WORLD);
    if (rank == 0) std::cout << "GPU roundtrip validation passed." << std::endl;

    check_cuda(cudaFree(d_buf));
    MPI_Finalize();
    return 0;
}
