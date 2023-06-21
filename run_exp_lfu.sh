#!/bin/bash

# import common functions
if [ "$BIGMEMBENCH_COMMON_PATH" = "" ] ; then
  echo "ERROR: bigmembench_common script not found. BIGMEMBENCH_COMMON_PATH is $BIGMEMBENCH_COMMON_PATH"
  echo "Have you set BIGMEMBENCH_COMMON_PATH correctly? Are you using sudo -E instead of just sudo?"
  exit 1
fi
source ${BIGMEMBENCH_COMMON_PATH}/run_exp_common.sh

RESULT_DIR="exp/exp_lfu_test/"
INPUT_DIR="/ssd1/songxin8/thesis/genomics/input-datasets/kmer-cnt/large/"
NUM_THREADS=16
MEMCONFIG=""
NUM_ITERS=1

run_app () {
  OUTFILE_NAME=$1 
  CONFIG=$2

  OUTFILE_PATH="${RESULT_DIR}/${OUTFILE_NAME}"

  if [[ "$CONFIG" == "ALL_LOCAL" ]]; then
    # All local config: place both data and compute on node 1
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --membind=1 --cpunodebind=1"
  elif [[ "$CONFIG" == "LFU" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "TPP" ]]; then
    # only use node 0 CPUs and let TPP decide how memory is placed
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "AUTONUMA" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "MULTICLOCK" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  elif [[ "$CONFIG" == "NO_TIERING" ]]; then
    COMMAND_COMMON="/usr/bin/time -v /usr/bin/numactl --cpunodebind=0"
  else
    echo "Error! Undefined configuration $CONFIG"
    exit 1
  fi

  echo "Start" > $OUTFILE_PATH
  echo "=======================" >> $OUTFILE_PATH
  echo "NUMA hardware config " >> $OUTFILE_PATH
  NUMACTL_OUT=$(numactl -H)
  echo "$NUMACTL_OUT" >> $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "Migration counters" >> $OUTFILE_PATH
  MIGRATION_STAT=$(grep -E "pgdemote|pgpromote|pgmigrate" /proc/vmstat)
  echo "$MIGRATION_STAT" >> $OUTFILE_PATH
  echo "=======================" >> $OUTFILE_PATH

  echo "${COMMAND_COMMON} ./bin/jellyfish count --no-write -m 28 -s 17G -t ${NUM_THREADS} -C ${INPUT_DIR}/Zymo-GridION-EVEN-BB-SN-PCR-R10HC-flipflop.fastq" >> $OUTFILE_PATH

  ${COMMAND_COMMON} ./bin/jellyfish count --no-write -m 28 -s 17G -t ${NUM_THREADS} -C ${INPUT_DIR}/Zymo-GridION-EVEN-BB-SN-PCR-R10HC-flipflop.fastq &>> $OUTFILE_PATH

  echo "=======================" >> $OUTFILE_PATH
  echo "Migration counters" >> $OUTFILE_PATH
  MIGRATION_STAT=$(grep -E "pgdemote|pgpromote|pgmigrate" /proc/vmstat)
  echo "$MIGRATION_STAT" >> $OUTFILE_PATH
  echo "=======================" >> $OUTFILE_PATH

  echo "Workload complete."
}


##############
# Script start
##############

mkdir -p $RESULT_DIR

# TinyLFU
echo "[INFO] Building Jellyfish for LFU"
make clean
make -j LOCAL_DEFS="-DLFU_TIERING"
BUILD_RET=$?
echo "Build return: $BUILD_RET"
if [ $BUILD_RET -ne 0 ]; then
  echo "ERROR: Failed to build Jellyfish"
  exit 1 
fi
for ((i=0;i<$NUM_ITERS;i++)); do
  enable_lfu
  clean_cache
  LOGFILE_NAME=$(gen_file_name "jellyfish" "ZymoGridIONEVEN" "${MEMCONFIG}_lfu" "iter$i")
  run_app $LOGFILE_NAME "LFU"
done


## AutoNUMA
#echo "[INFO] Building Jellyfish for AutoNUMA"
#make clean
#make -j 
#BUILD_RET=$?
#echo "Build return: $BUILD_RET"
#if [ $BUILD_RET -ne 0 ]; then
#  echo "ERROR: Failed to build Jellyfish"
#  exit 1 
#fi
#for ((i=0;i<$NUM_ITERS;i++)); do
#  enable_autonuma "MGLRU"
#  clean_cache
#  LOGFILE_NAME=$(gen_file_name "jellyfish" "ZymoGridIONEVEN" "${MEMCONFIG}_autonuma" "iter$i")
#  run_app $LOGFILE_NAME "AUTONUMA"
#done
