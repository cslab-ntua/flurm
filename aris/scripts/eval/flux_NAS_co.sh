#!/bin/bash -l
BASE_DIR=$HOME/kkats

LOG_PATH=$BASE_DIR/eval/flux_logs/$2.$3_$4.$5
mkdir -p $LOG_PATH

# always put app with the lowest procs first
PROCS=$3
PROCS2=$5
intprocs=$((PROCS))
intprocs2=$((PROCS2))

if (( ${intprocs} > ${intprocs2} )); then
        min=$PROCS2
        max=$PROCS
        argmin=$4
        argmax=$2
else
        min=$PROCS
        max=$PROCS2
        argmin=$2
        argmax=$4
fi
control=$1
copies=$(( ${max} / ${min} ))
echo "${argmin}_${argmax},${copies},${max},${min}"
find  "${LOG_PATH}" -maxdepth 1 -name 'pipe' -exec rm {} \;

min_start=$(date +%s)
# Start the min applications to the correct nodes
for (( i=0; i<${copies}; i++ ))
do
    {
        touch ${LOG_PATH}/${argmin}_${argmax}_${i}.out
        chmod +rw ${LOG_PATH}/${argmin}_${argmax}_${i}.out
        while [ ! -f ${LOG_PATH}/pipe ]; do

            app_start=$(date +%s)

            flux run --requires="-hosts:$control" --alloc-type=spread -n $min $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/$argmin 1>> ${LOG_PATH}/${argmin}_${argmax}_${i}.out

            app_end=$(date +%s)

            difference=$((app_end - app_start))
            echo "DATE of $argmin in seconds: $difference" 1>> $LOG_PATH/${argmin}_${argmax}_${i}.out

        done

    } &
done

max_start=$(date +%s)

{
    touch ${LOG_PATH}/${argmax}_${argmin}_${i}.out
    chmod +rw ${LOG_PATH}/${argmax}_${argmin}_${i}.out
    while [ ! -f ${LOG_PATH}/pipe ]; do

        app_start=$(date +%s)

        flux run --requires="-hosts:$control" --alloc-type=spread -n $max $BASE_DIR/NPB3.4.3/NPB3.4-MPI/bin/$argmax 1>> ${LOG_PATH}/${argmax}_${argmin}_${i}.out

        app_end=$(date +%s)

        difference=$((app_end - app_start))
        echo "DATE of $argmax in seconds: $difference" 1>> $LOG_PATH/${argmax}_${argmin}_${i}.out
    done

} &


sleep 600
touch $LOG_PATH/pipe