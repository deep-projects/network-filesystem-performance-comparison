#!/bin/bash

# Global options to configure benchmarking
DO_MEMORY_BENCHMARK=0
DO_LOCAL_IO_BENCHMARK=0
DO_CPU_BENCHMARK=0
DO_IO_WRITE_TEST=0
DO_NFS_IO_BENCHMARK=1
DO_SSHFS_IO_BENCHMARK=1
DO_HTTPFS_IO_BENCHMARK=1
DO_HTTPFS_SECURE_IO_BENCHMARK=0
DO_NETWORK_BENCHMARK=0

WAIT_BETWEEN_IO_TESTS=0

# Block sizes to test in io benchmark
IO_RUNS=1
IO_BLOCKSIZES="8M 16M"
IO_PARALLEL_JOBS=1

HOST=$(hostname -s)
HOST_NUMBER=$(echo ${HOST} | egrep -o "[1-9]+")

# Directory to perform local io measures in
LOCAL_IO_BENCHMARK_DIR="/nvme"

# Directory to perform nfs io measures in
NFS_BENCHMARK_DIR="/data/benchmark"
NFS_KERBEROS_BENCHMARK_DIR="/mnt/benchmark"

# Remote directory, user and host to bind for sshfs io measures
SSHFS_BENCHMARK_DIR="/data/benchmark"
SSHFS_BENCHMARK_USER="local"
SSHFS_BENCHMARK_HOST="avocado01.f4.htw-berlin.de"

# Remote directory, user and host to bind for sshfs io measures
HTTPFS_BENCHMARK_URL="http://avocado01.f4.htw-berlin.de/benchmark"
HTTPFS_BENCHMARK_SECURE_URL="https://avocado01.f4.htw-berlin.de/benchmark"
HTTPFS_BENCHMARK_USER="USERNAME"
HTTPFS_BENCHMARK_PASSWORD="PASSWORD"
HTTPFS_BENCHMARK_PROXY_OPTION=""

# Network measurements setup (host, connect user and number pf executions)
NETWORK_BENCHMARK_HOST="avocado01.f4.htw-berlin.de"
NETWORK_BENCHMARK_USER="local"
NETWORK_BENCHMARK_PORT=$((12345+${HOST_NUMBER}))
NUM_NETWORK_RUNS=3

# Clean caches after each execution
CLEAN_CACHE_AFTER_TEST=1

# Some variables for file creation
TIMESTAMP=$(date "+%s")
if [ "x${2}" == "x" ]
then
	OUTPUT_DIR="/root/benchmark_results/${TIMESTAMP}"
else
	OUTPUT_DIR="${2}/${TIMESTAMP}"
fi
mkdir -p "${OUTPUT_DIR}"

if [ "x${1}" == "x" ]
then
	SHARE_DIR_SUFFIX=""
else
	SHARE_DIR_SUFFIX="${1}"
	OUTPUT_DIR="${OUTPUT_DIR}_${SHARE_DIR_SUFFIX}"
fi
mkdir -p "${OUTPUT_DIR}"

# Load cache clear command
if [ ${CLEAN_CACHE_AFTER_TEST} -eq 1 ]
then
	CC="bash -c sync; echo 3 > /proc/sys/vm/drop_caches"
	c="nocache"
else
	CC=""
	c="cache"
fi

function wait_if_required {
	if [ ${WAIT_BETWEEN_IO_TESTS} -eq 1 ]
	then
		#echo -ne "Enter to continue test"
		#read _
		ls /tmp/__sem*.${1} > /dev/null 2>&1
		while [ $? -eq 0 ]
		do
			sleep 1
			echo "Waiting..."
			ls /tmp/__sem*.${1} > /dev/null 2>&1
		done
	fi
}

# Sysbench fs test base command
BENCH_CPU="sysbench --debug=on"
BENCH_MEMORY="sysbench --debug=on --test=memory --memory-total-size=64G"
BENCH_IO="fio --output-format=json --runtime=60s --numjobs=${IO_PARALLEL_JOBS} --iodepth=1 --loops=${IO_RUNS} --size=2G --name=benchmark-${HOST} --ioengine=sync --fallocate=none"

# No more configuration beyond this point
echo "Run benchmark - save results to ${OUTPUT_DIR}"

# CPU
if [ ${DO_CPU_BENCHMARK} -eq 1 ]
then
	echo "  Running CPU benchmark"
	${BENCH_CPU} --test=cpu run > "${OUTPUT_DIR}/${HOST}.cpu.txt" 2>&1
	${BENCH_CPU} --test=threads --num-threads=64 run > "${OUTPUT_DIR}/${HOST}.cpu.threads.txt" 2>&1
	${BENCH_CPU} --test=mutex --mutex-num=4096 --memory-total-size=128G --memory-oper=read run > "${OUTPUT_DIR}/${HOST}.cpu.mutex.read.txt" 2>&1
	${BENCH_CPU} --test=mutex --mutex-num=4096 --memory-total-size=128G --memory-oper=write run > "${OUTPUT_DIR}/${HOST}.cpu.mutex.write.txt" 2>&1
fi # if DO_CPU_BENCHMARK

# Memory 
if [ ${DO_MEMORY_BENCHMARK} -eq 1 ]
then
	echo "  Running memory benchmark"

	for blocksize in 4M 8M 16M 32M 64M 128M
	do
		echo "  - Test with blocksize=${blocksize}M"
		
		# mem write
		echo "    - Write"
		${BENCH_MEMORY} --memory-block-size=${blocksize} --memory-oper=write --memory-access-mode=seq run > "${OUTPUT_DIR}/${HOST}.memory.write.sequential.b${blocksize}.txt" 2>&1
		${BENCH_MEMORY} --memory-block-size=${blocksize} --memory-oper=write --memory-access-mode=rnd run > "${OUTPUT_DIR}/${HOST}.memory.write.random.b${blocksize}.txt" 2>&1

		# mem read
		echo "    - Read"
		${BENCH_MEMORY} --memory-block-size=${blocksize} --memory-oper=read --memory-access-mode=seq run > "${OUTPUT_DIR}/${HOST}.memory.read.sequential.b${blocksize}.txt" 2>&1
		${BENCH_MEMORY} --memory-block-size=${blocksize} --memory-oper=read --memory-access-mode=rnd run > "${OUTPUT_DIR}/${HOST}.memory.read.random.b${blocksize}.txt" 2>&1
	done
fi # if DO_MEMORY_BENCHMARK

# Network
if [ "${DO_NETWORK_BENCHMARK}" -eq 1 ]
then
	echo "  Running network benchmark"	
	for ((i=1;i<=${NUM_NETWORK_RUNS};i++))
	do
		echo "  - Test TCP (run ${i})" 
		ssh ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST} "iperf -s -p ${NETWORK_BENCHMARK_PORT} -D"
		iperf -e -t 10 -c ${NETWORK_BENCHMARK_HOST} -p ${NETWORK_BENCHMARK_PORT} -r > "${OUTPUT_DIR}/${HOST}.net.tcp.${i}.txt" 2>&1
		ssh ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST} "killall iperf"
	done

	for ((i=1;i<=${NUM_NETWORK_RUNS};i++))
	do
		echo "  - Test UDP (run ${i})" 
		ssh ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST} "iperf -s -u -p ${NETWORK_BENCHMARK_PORT} -D"
		iperf -e -t 10 -c ${NETWORK_BENCHMARK_HOST} -p ${NETWORK_BENCHMARK_PORT} -r -u > "${OUTPUT_DIR}/${HOST}.net.udp.${i}.txt" 2>&1
		ssh ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST} "killall iperf"
	done
fi # if DO_NETWORK_BENCHMARK 

# Local IO-Benchmark
if [ ${DO_LOCAL_IO_BENCHMARK} -eq 1 ]
then
	iotype="fileio"
	echo "  Running local IO benchmark"
	pushd "${LOCAL_IO_BENCHMARK_DIR}"
	
	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file write
		if [ ${DO_IO_WRITE_TEST} -eq 1 ]
		then
			echo "    - Write"
			touch "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.nosync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.nosync.${c}.b${blocksize}.txt"; ${CC}
			rm "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			wait_if_required b${blocksize}.${iotype}
		fi # if DO_IO_WRITE_TEST

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done
	
	popd
fi # if DO_LOCAL_IO_BENCHMARK

# SSH IO-Benchmark
if [ "${DO_SSHFS_IO_BENCHMARK}" -eq 1 ]
then
	iotype="sshfsio"
	echo "  Running SSHFS IO benchmark"

	share_dir="/tmp/sshfsbench${SHARE_DIR_SUFFIX}"
	mkdir -p "${share_dir}"
	sshfs -o Cipher=aes128-cbc -o cache_timeout=115200 -o attr_timeout=115200 -o  no_readahead ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST}:${SSHFS_BENCHMARK_DIR} "${share_dir}"
	pushd "${share_dir}"

	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file write
		if [ ${DO_IO_WRITE_TEST} -eq 1 ]
		then
			echo "    - Write"
			touch "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.nosync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.nosync.${c}.b${blocksize}.txt"; ${CC}
			rm "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			wait_if_required b${blocksize}.${iotype}
		fi # if DO_IO_WRITE_TEST

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
	umount "${share_dir}"
	
	iotype="sshfsnochipherio"
	echo "  Running SSHFS Cipher=none IO benchmark"

	mkdir -p "${share_dir}"
	sshfs -o Cipher=none -o cache_timeout=115200 -o attr_timeout=115200 -o  no_readahead ${NETWORK_BENCHMARK_USER}@${NETWORK_BENCHMARK_HOST}:${SSHFS_BENCHMARK_DIR} "${share_dir}"
	pushd "${share_dir}"

	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file write
		if [ ${DO_IO_WRITE_TEST} -eq 1 ]
		then
			echo "    - Write"
			touch "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.nosync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.nosync.${c}.b${blocksize}.txt"; ${CC}
			rm "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			wait_if_required b${blocksize}.${iotype}
		fi # if DO_IO_WRITE_TEST

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
	umount "${share_dir}"
	
fi # if DO_SSHFS_IO_BENCHMARK

# NFS-Benchmark
if [ "${DO_NFS_IO_BENCHMARK}" -eq 1 ]
then
	iotype="nfsio"
	echo "  Running NFS IO benchmark"
	pushd "${NFS_BENCHMARK_DIR}"

	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file write
		if [ ${DO_IO_WRITE_TEST} -eq 1 ]
		then
			echo "    - Write"
			touch "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.nosync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.nosync.${c}.b${blocksize}.txt"; ${CC}
			rm "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			wait_if_required b${blocksize}.${iotype}
		fi # if DO_IO_WRITE_TEST

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
	
	iotype="nfskrbio"
	echo "  Running NFS Kerberos IO benchmark"
	pushd "${NFS_KERBEROS_BENCHMARK_DIR}"

	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file write
		if [ ${DO_IO_WRITE_TEST} -eq 1 ]
		then
			echo "    - Write"
			touch "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=write --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.sequential.nosync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=1 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.sync.${c}.b${blocksize}.txt"; ${CC}
			${BENCH_IO} --bs=${blocksize} --rw=randwrite --fsync=0 --output="${OUTPUT_DIR}/${HOST}.${iotype}.write.random.nosync.${c}.b${blocksize}.txt"; ${CC}
			rm "/tmp/__sem${SHARE_DIR_SUFFIX}.b${blocksize}.${iotype}"
			wait_if_required b${blocksize}.${iotype}
		fi # if DO_IO_WRITE_TEST

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
fi # if DO_NFS_IO_BENCHMARK

# HTTPFS IO-Benchmark
if [ "${DO_HTTPFS_IO_BENCHMARK}" -eq 1 ]
then
	iotype="httpfsio"
	echo "  Running HTTPFS IO benchmark"

	share_dir="/tmp/httpfsbench${SHARE_DIR_SUFFIX}"
	mkdir -p "${share_dir}"
	httpdirfs -u ${HTTPFS_BENCHMARK_USER} -p ${HTTPFS_BENCHMARK_PASSWORD} ${HTTPFS_BENCHMARK_PROXY_OPTION} ${HTTPFS_BENCHMARK_URL} "${share_dir}"
	pushd "${share_dir}"
	
	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
	umount "${share_dir}"
fi # if DO_HTTPFS_BENCHMARK

# HTTPFS secure IO-Benchmark
if [ "${DO_HTTPFS_SECURE_IO_BENCHMARK}" -eq 1 ]
then
	iotype="httpsfsio"
	echo "  Running HTTPFS secure IO benchmark"

	share_dir="/tmp/httpfsbench${SHARE_DIR_SUFFIX}"
	mkdir -p "${share_dir}"
	httpdirfs -u ${HTTPFS_BENCHMARK_USER} -p ${HTTPFS_BENCHMARK_PASSWORD} ${HTTPFS_BENCHMARK_PROXY_OPTION} ${HTTPFS_BENCHMARK_SECURE_URL} "${share_dir}"
	pushd "${share_dir}"
	
	for blocksize in ${IO_BLOCKSIZES}
	do
		echo "  - Test with blocksize=${blocksize}"

		# file read
		echo "    - Read"
		touch "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		${BENCH_IO} --bs=${blocksize} --rw=read --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.sequential.${c}.b${blocksize}.txt"; ${CC}
		${BENCH_IO} --bs=${blocksize} --rw=randread --output="${OUTPUT_DIR}/${HOST}.${iotype}.read.random.${c}.b${blocksize}.txt"; ${CC}
		rm "/tmp/__sem${SHARE_DIR_SUFFIX}.read.${iotype}"
		wait_if_required read.${iotype}
	done

	popd
	umount "${share_dir}"
fi # if DO_HTTPFS_SECURE_IO_BENCHMARK
