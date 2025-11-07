#!/bin/bash -l
BASE_DIR=$HOME/kkats

LOG_PATH=$BASE_DIR/eval/flux_logs/$2.$3
mkdir -p $LOG_PATH

# always put app with the lowest procs first
PROCS=$3
arg=$2
control=$1
echo "${arg}$,${PROCS}"
find  "${LOG_PATH}" -maxdepth 1 -name 'pipe' -exec rm {} \;

min_start=$(date +%s)
# Start the min applications to the correct nodes
{
    touch ${LOG_PATH}/${arg}.out
    chmod +rw ${LOG_PATH}/${arg}.out
    while [ ! -f ${LOG_PATH}/pipe ]; do

        app_start=$(date +%s)

        flux run --requires="-hosts:$control" --alloc-type=spread -n $PROCS $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/$arg 1>> ${LOG_PATH}/${arg}.out

        app_end=$(date +%s)

        difference=$((app_end - app_start))
        echo "DATE of $arg in seconds: $difference" 1>> $LOG_PATH/${arg}.out
    done

} &


sleep 600
touch $LOG_PATH/pipe