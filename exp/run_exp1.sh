#!/bin/bash

# Run experiments that place all data structures on node 0 DRAM vs node 1 DRAM.

INPUT_DIR="/ssd1/songxin8/thesis/genomics/input-datasets/kmer-cnt/large/"
NUM_THREADS=16
RESULT_DIR="exp1"

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $LOG_PID."
    # Perform program exit housekeeping
    kill $LOG_PID
    kill $EXE_PID
    exit
}

clean_cache () { 
  echo "Clearing caches..."
  # clean CPU caches
  ./tools/clear_cpu_cache
  # clean page cache
  echo 3 > /proc/sys/vm/drop_caches
}

run_SRR6702603_1() { 
  OUTFILE=$1 #first argument
  NODE=$2
  echo "Start" > $OUTFILE
  
  INPUT_FILE_NAME="${INPUT_DIR}/SRR6702603_1.fastq "
  # To run jellyfish for multiple iterations, provide the same input file to jellyfish
  # multiple times. 
  # ./bin/jellyfish count file1 file1 file1 file1  # runs file1 for 4 iterations.

  # fancy way of generating the input file name 10 times
  # run for 10 iterations to get good profiling
  INPUT_ARG=$(printf "$INPUT_FILE_NAME%.0s" {1..10})
  echo "INPUT ARG: $INPUT_ARG"
  /usr/bin/time -v /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
       ../bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG &>> $OUTFILE &
  TIME_PID=$! 
  EXE_PID=$(pgrep -P $TIME_PID)

  echo "EXE PID is ${EXE_PID}"
  echo "start" > ${OUTFILE}_numastat
  while true; do numastat -p $EXE_PID >> ${OUTFILE}_numastat; sleep 2; done &
  LOG_PID=$!

  echo "Waiting for kernel to complete (PID is ${EXE_PID}). numastat is logged into ${OUTFILE}_numastat, PID is ${LOG_PID}" 
  wait $TIME_PID
  echo "GAP kernel complete."
  kill $LOG_PID
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

mkdir -p $RESULT_DIR

clean_cache
run_SRR6702603_1 "${RESULT_DIR}/SRR6702603_1_${NUM_THREADS}threads_allnode0" 0
#clean_cache                                                                
#run_SRR6702603_1 "${RESULT_DIR}/SRR6702603_1_${NUM_THREADS}threads_allnode1" 1

