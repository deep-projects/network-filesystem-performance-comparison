# Network Filesystem Performance Comparison

This repository acompanies a publication and provides shell scripts to measure the performance of different network filesystems. It contains two types of experiments.


## Type 1: Random read speed for one large artificial file

1. Install sysbench, SSHFS, NFS, HTTPDirFS.
2. Setup data sources for the network filesystems.
3. Adapt paths in the `do_benchmark_pepper.sh` bash script.
4. Run the script.

```bash
./do_benchmark_pepper.sh
```


## Type 2: Performance of containerized CNN training, with NFS or SSD storage mounted in the container

1. Install Docker and Nvidia-Docker2.
2. Generate a large `merged.hdf5` dataset as described in [camelyon-experiments-v2](https://github.com/deep-projects/camelyon-experiments-v2).
3. Store the file on a local SSD or on a remote NFS share.
4. Adapt paths in the `run_training_experiments` bash script. 
5. Run the script.

```bash
./run_training_experiments
```
