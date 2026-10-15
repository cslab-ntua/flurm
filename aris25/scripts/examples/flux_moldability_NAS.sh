#!/bin/bash -l
BASE_DIR=$HOME/kkats

control=$1

LOG_PATH=$BASE_DIR/moldability/flux_logs
mkdir -p $LOG_PATH


flux run --requires="-hosts:$control" -S task_counts="[128,67,42]" -S durations="[116.625, 69, 17]" $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/cg.D.x 1>> ${LOG_PATH}/cg.D.x.out 
flux run --requires="-hosts:$control" -S task_counts="[64,67,42]" -S durations="[25.1375, 1, 2]" $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/sp.C.x 1>> ${LOG_PATH}/sp.C.x.out
flux run --requires="-hosts:$control" -S task_counts="[64,67,42]" -S durations="[1, 1, 2]" $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/sp.C.x 1>> ${LOG_PATH}/sp.C.x_small_walltime.out
flux run --requires="-hosts:$control" -S task_counts="[128,69,41]" -S durations="[173.1375, 67, 0.42]" $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/lu.D.x 1>> ${LOG_PATH}/lu.D.x.out 