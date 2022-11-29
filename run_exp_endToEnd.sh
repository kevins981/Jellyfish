#!/bin/bash

# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

INPUT_DIR="/ssd1/songxin8/thesis/genomics/input-datasets/kmer-cnt/large/"
NUM_THREADS=16
MEMCONFIG="${NUM_THREADS}threads"

#RESULT_DIR="exp/exp_endToEnd"
RESULT_DIR="exp/test"

clean_up () {
    echo "Cleaning up. Kernel PID is $EXE_PID, numastat PID is $NUMASTAT_PID, top PID is $TOP_PID."
    # Perform program exit housekeeping
    kill $NUMASTAT_PID
    kill $TOP_PID
    kill $EXE_PID
    exit
}

run_app () { 
  OUTFILE_NAME=$1
  CONFIG=$2

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=1 --cpunodebind=1"
  elif [[ "$CONFIG" == "EDGES_ON_REMOTE" ]]; then
    # place edges array on node 1, rest on node 0
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=0 --cpunodebind=0"
  elif [[ "$CONFIG" == "TPP" ]]; then
    # only use node 0 CPUs and let TPP decide how memory is placed
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "AUTONUMA" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE_PATH

  echo "NUMA hardware config is: " >> $OUTFILE_PATH
  NUMACTL_OUT=$(numactl -H)
  echo "$NUMACTL_OUT" >> $OUTFILE_PATH

  INPUT_FILE_NAME="${INPUT_DIR}/SRR6702603_1.fastq "
  # To run jellyfish for multiple iterations, provide the same input file to jellyfish
  # multiple times. 
  # ./bin/jellyfish count file1 file1 file1 file1  # runs file1 for 4 iterations.

  # fancy way of generating the input file name 10 times
  # run for 10 iterations to get good profiling
  INPUT_ARG=$(printf "$INPUT_FILE_NAME%.0s" {1..10})
  echo "Running command: ${COMMAND_COMMON} ./bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG" >> $OUTFILE_PATH
  ${COMMAND_COMMON} ./bin/jellyfish count -m 25 -s 8G -t ${NUM_THREADS} -C $INPUT_ARG &>> $OUTFILE_PATH &
  TIME_PID=$! 
  EXE_PID=$(pgrep -P $TIME_PID)

  echo "EXE PID is ${EXE_PID}"
  echo "start" > ${OUTFILE_PATH}-numastat
  while true; do numastat -p $EXE_PID >> ${OUTFILE_PATH}-numastat; sleep 2; done &
  NUMASTAT_PID=$!
  top -b -d 10 -1 -p $EXE_PID > ${OUTFILE_PATH}-toplog &
  TOP_PID=$!

  echo "Waiting for kernel to complete (PID is ${EXE_PID}). numastat is logged into ${OUTFILE_PATH}-numastat, PID is ${NUMASTAT_PID}. Top PID is ${TOP_PID}" 
  wait $TIME_PID
  echo "GAP kernel complete."
  kill $NUMASTAT_PID
  kill $TOP_PID
}


##############
# Script start
##############
trap clean_up SIGHUP SIGINT SIGTERM

mkdir -p $RESULT_DIR

echo "NUMA hardware config is: "
NUMACTL_OUT=$(numactl -H)
echo "$NUMACTL_OUT"

## TPP
#enable_tpp
#clean_cache
#LOGFILE_NAME=$(gen_file_name "jellyfish" "SRR6702603_1" "${MEMCONFIG}_tpp")
#run_app $LOGFILE_NAME "TPP"

# AutoNUMA
enable_autonuma
clean_cache
LOGFILE_NAME=$(gen_file_name "jellyfish" "SRR6702603_1" "${MEMCONFIG}_autonuma")
run_app $LOGFILE_NAME "AUTONUMA"

# All on local memory node
disable_numa
clean_cache
LOGFILE_NAME=$(gen_file_name "jellyfish" "SRR6702603_1" "${MEMCONFIG}_allLocal")
run_app $LOGFILE_NAME "ALL_LOCAL"
