<img src="logo.png" alt="Flurm Logo" width="500">

# A framework for flexible fine-grained resource management and job scheduling in HPC systems.

**Contributors:** Konstantinos Katsikopoulos

## Overview

Flurm is a user-level framework that leverages Flux under Slurm (hence "Flurm") to enable advanced resource management and job scheduling in High-Performance Computing (HPC) environments, such as the ARIS cluster. It allows users to achieve fine-grained control over resources without administrative privileges, including compact and spread allocations, custom scheduling algorithms, and support for co-scheduling jobs.

This repository provides scripts, templates, and examples to install and use Flux in a Slurm-managed cluster, model system resources as graphs, define custom jobspecs, and run experiments like those on NAS Parallel Benchmarks.

## Repository Layout
- [`aris/`](./aris)
Scripts, templates, and helper tools used on the ARIS supercomputer.

- [`docker/`](./docker)
A Docker-based simulation of a Flurm cluster.

## Agenda

- Fine grained resource control e.g. compact - spread allocation
- Custom scheduling algorithms
- Support for co-scheduling

*All of these as an ARIS cluster user!*

## Flux Introduction

Flux is a next-generation resource and job management framework that expands the scheduler's view beyond the single dimension of "nodes." Instead of simply developing a replacement for SLURM, Flux offers a framework that enables new resource types, schedulers, and framework services to be deployed under SLURM or on their own.

### What is Flux?

Flux provides a flexible foundation for managing HPC resources, allowing users to interact with a system in a more granular way compared to traditional schedulers.

## Flux Overview

The Flux architecture includes:
- **Management Node:** Hosts the `flux-broker` (rank 0) with KVS backing store and system admin functions.
- **Login Node:** Runs `flux-broker` with user-initiated tasks like `flux batch`.
- **Compute Nodes:** Managed by `flux-broker-shell` processes.
- **Overlay Network:** A tree-based network connecting all nodes.

## Flux Broker Architecture

The Flux Broker consists of:
- **PMI Client**
- **Broker State Machine**
- **Broker Module Management**
- **Broker Core Services**
- **Message Routing**
- **ØMQ** (ZeroMQ for messaging)

## Flux Instance Network

Flux instances are organized with a leader-follower model:
- One node acts as the Leader.
- Other nodes are Followers, connected via an overlay network.

## Flux Framework is a Suite of Projects

- **Core Projects:** `flux-core`, `flux-sched`, `flux-security`, `flux-accounting`
- **Associated Projects:** `flux-pmix`, `flux-restful-api`, `flux-operator`, `flux-python`, ...

## Projects Work Together to Encompass "Flux"

- **flux-core:**
  1. Command line client (e.g., `flux run`, ...)
  2. Job management, transformation, validation
  3. Messages and events
- **flux-sched:**
  1. Resource definition (e.g., json, xml, etc.)
  2. Queueing
  3. Resource graph (vertices: nodes, cores, socket, etc.; edges: "node contains core1")
  4. Query interface

## flux-core is What You Interact With to Manage Jobs

- Use `flux-core` for:
  - "I want to run a job with these resources"
  - "I want to watch and respond to job events"
  - "I want to cancel a job"
  - "I want to check my job status"
  - "I want to write a plugin to validate jobs"

## Some Flux Commands

Here are how flux commands map to a scheduler you are likely familiar with, Slurm.

| Operation                  | Slurm              | Flux                     |
|----------------------------|--------------------|--------------------------|
| One-off run of a single job (blocking) | srun               | flux run                 |
| One-off run of a single job (interactive) | srun --pty         | flux run -o pty.interactive |
| One-off run of a single job (not blocking) | NA                 | flux submit              |
| Bulk submission of jobs (not blocking) | NA                 | flux bulksubmit          |
| Watching jobs              | NA                 | flux watch               |
| Querying the status of jobs | squeue/scontrol show job job_id | flux jobs/flux job info job_id |
| Canceling running jobs     | scancel            | flux cancel              |
| Allocation for an interactive instance | salloc             | flux alloc               |
| Submitting batch jobs      | sbatch             | flux batch               |

## More Flux Commands

- `flux job attach <job_id>`
- `flux start` (one useful argument is `--test-size`)
- `flux resource list`
- `flux getattr <attribute>`
- `flux queue disable "<message string>"`
- `flux queue enable`

## flux-sched is Modeling Your System as a Graph

- **flux-sched** process:
  1. Resource definition (e.g., json, xml, etc.)
  2. Queueing
  3. Resource graph (vertices: nodes, cores, socket, etc.; edges: "node contains core1")
  4. Query interface

## Features

- Fine-grained resource control (e.g., compact and spread allocations)
- Custom scheduling algorithms
- Support for co-scheduling
- User-level installation via Spack
- Resource modeling with JSON Graph Format (JGF) and R files
- Python API integration for job management

All features are designed for use as a regular cluster user, expanding beyond Slurm's node-centric view.

## Installation

Flurm relies on Flux installed via Spack, an HPC package manager.

**Install Spack and Flux using the provided script:**
   - Customize user config and cache paths if needed.
   - Run the custom bash script `spack_install_flux.sh` (included in this repo) to install Flux and dependencies (flux-core, flux-sched) in your home directory.
   - This handles versioning, dependencies, and builds Flux in userspace like a virtual environment.

Required modules for running Flux (example for ARIS cluster):
- `module load gnu/8`
- `module load gnu/13.2.0`
- `module load python/3.9.18`
- `module load git`
- `module load intel/19`
- `module load intelmpi/2018`

After installation, you can load the Spack environment and the Flux module like so: 
- `. spack/share/spack/setup-env.sh`
- `spack load flux-sched`

## Usage

### Basic Workflow

Use the provided `flux_template.sh` script as a Slurm batch job template. It allocates nodes via Slurm, starts a Flux instance, and runs your application.

Example (`flux_template.sh` excerpt):

```bash
#!/bin/bash -l

#SBATCH --job-name=FluxTest
#SBATCH --output=FluxTest.%j.out
#SBATCH --error=FluxTest.%j.err
#SBATCH --ntasks=3
#SBATCH --nodes=3
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --mem-per-cpu=2400
#SBATCH --exclusive

# Load modules and set environment (as above)

# Start Flux and run your command
srun -N $SLURM_JOB_NUM_NODES -n $SLURM_JOB_NUM_NODES --mpi=pmi2 --export=ALL flux start \
    flux run --requires="hosts:${COMPUTE_NODELIST}" -N $NNODES -n $NTASKS hostname  # Replace 'hostname' with your app
```

Submit with: sbatch flux_template.sh
