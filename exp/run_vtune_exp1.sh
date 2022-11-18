#!/bin/bash

# Run experiments that place all data structures on node 0 DRAM vs node 1 DRAM.

INPUT_DIR="/ssd1/songxin8/thesis/genomics/input-datasets/kmer-cnt/large/"
NUM_THREADS=16
RESULT_DIR="/ssd1/songxin8/thesis/genomics/vtune/Jellyfish/exp1/"

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

run_vtune_SRR6702603_1() { 
  OUTFILE=$1 #first argument
  NODE=$2

  VTUNE_MEMACC_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect memory-access \
      -knob sampling-interval=10 -knob analyze-mem-objects=true -knob analyze-openmp=true \
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_memacc"

  VTUNE_HOTSPOT_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect hotspots \
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_hotspot"

  VTUNE_UARCH_COMMON="/opt/intel/oneapi/vtune/latest/bin64/vtune -collect uarch-exploration \
      -knob sampling-interval=10 -knob collect-memory-bandwidth=true
      -data-limit=10000 -result-dir ${RESULT_DIR}/${OUTFILE}_uarch"
      #--app-working-dir=/ssd1/songxin8/thesis/graph/gapbs"
  
  
  INPUT_FILE_NAME="${INPUT_DIR}/SRR6702603_1.fastq "
  # To run jellyfish for multiple iterations, provide the same input file to jellyfish
  # multiple times. 
  # ./bin/jellyfish count file1 file1 file1 file1  # runs file1 for 4 iterations.

  # fancy way of generating the input file name 10 times
  INPUT_ARG=$(printf "$INPUT_FILE_NAME%.0s" {1..10})

  echo "Running memory access analysis. Log is at ${RESULT_DIR}/${OUTFILE}_memacc_log"
  ${VTUNE_MEMACC_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
       ../bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG &> ${RESULT_DIR}/${OUTFILE}_memacc_log

  clean_cache

  echo "Running uarch analysis. Log is at ${RESULT_DIR}/${OUTFILE}_uarch_log"
  ${VTUNE_UARCH_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
       ../bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG &> ${RESULT_DIR}/${OUTFILE}_uarch_log

  #clean_cache

  #echo "Running hotspot analysis. Log is at ${RESULT_DIR}/${OUTFILE}_hotspot_log"
  #${VTUNE_HOTSPOT_COMMON} -- /usr/bin/numactl --membind=${NODE} --cpunodebind=0 \
  #     ../bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG &> ${RESULT_DIR}/${OUTFILE}_hotspot_log
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

[[ $EUID -ne 0 ]] && echo "This script must be run using sudo or as root." && exit 1

mkdir -p $RESULT_DIR

clean_cache
run_vtune_SRR6702603_1 "SRR6702603_1_${NUM_THREADS}threads_allnode0" 0
#clean_cache                                                                
#run_vtune_SRR6702603_1 "SRR6702603_1_${NUM_THREADS}threads_allnode1" 1

