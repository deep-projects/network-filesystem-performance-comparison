# Network Filesystem Performance Comparison

This repository acompanies a publication and provides shell scripts to measure the performance of different network filesystems. It contains two types of experiments.

## Type 1: Random read speed for one large artificial file

TODO

## Type 2: Performance of containerized CNN training, with NFS or SSD storage mounted in the container

1. Install Docker and Nvidia-Docker2.
2. Generate a large `merged.hdf5` dataset as described in [camelyon-experiments-v2](https://github.com/deep-projects/camelyon-experiments-v2).
3. Store the file on a local SSD or on a remote NFS share.
4. Adapt paths in the `run_training_experiments`. 
5. Run the script.


```bash
./run_training_experiments
```
