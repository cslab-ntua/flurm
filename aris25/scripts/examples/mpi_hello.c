#include <stdio.h>
#include <mpi.h>
#include <sched.h>

int main(int argc, char *argv[]) {
    MPI_Init(&argc, &argv);
    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    char hostname[256];
    gethostname(hostname, sizeof(hostname));
    printf("Hello from rank %d of %d on %s (pid: %d, cpu: %d)\n", rank, size, hostname, getpid(), sched_getcpu());
    MPI_Finalize();

    return 0;
}