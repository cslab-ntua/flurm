# Flurm on ARIS

This folder contains scripts and helpers for running **Flux inside Slurm** on the **ARIS HPC system**.  
Slurm acts as the total resource allocator, while Flux runs as the inner resource manager and job scheduler.

---

## Contents

- **`opt/`**
  - `flux_helpers/` → Essential helpers making Flux work in ARIS.
  - `spack_install_flux.sh` → Script to install Flux and dependencies via [Spack](https://spack.readthedocs.io/).

- **`scripts/`**
  - `flux_template.sh` → A Slurm job submission template that launches Flux inside your allocation.
  - `check_ghosts.sh` → Script to detect and clean up leftover/“ghost” processes or jobs.
  - `jgf_gen.py` → Script to generate a JSON Graph Format (JGF) resource description for Flux.
  - `examples/` → Scripts for example use cases.
  - `eval/` → Scripts for flurm evaluation.

- **`conf.d/`**
  - `flux-config.toml` → Example Flux configuration file for ARIS.
  - `R.template` → The template for a R file for ARIS. `TEMPLATE_RANKLIST` and `TEMPLATE_HOSTLIST` should be replaced with the actual ranklist and hostlist.

---

## Usage on ARIS

1. **Install Flux and Spack**
   - The `spack_install_flux.sh` script will install Spack and use it to install Flux and its dependencies in your home directory.  
   - You only need to do this once.
   - You can customize the spack user config and user cache paths by defining the `SPACK_USER_CONFIG_PATH` and `SPACK_USER_CACHE_PATH` environment variables before running the script. If left unset the default paths are `~/.spack`. In the install script the default is `$(pwd)/.spack` for both of them.
   - In order for Flux to work properly on ARIS, you need to run `make` inside the `flux-helpers` directory after running the installation script.
```bash
git clone https://github.com/cslab-ntua/flurm.git
cd flurm/aris/opt/
./spack_install_flux.sh
cd flux_helpers
make
```
2. **Submit Jobs**
   - Use the `flux_template.sh` script as a starting point for your Slurm job scripts.  
   - It will allocate resources, load the Flux module, and launch a Flux broker inside your Slurm allocation. One node is used as the Flux control node, while the rest are used as compute nodes.
   - It uses `jgf_gen.py` to generate a JSON Graph Format (JGF) resource description for Flux based on your Slurm allocation (`aris.json`) and replaces the placeholders in the `R.template` file to create a R file for your system.
   - Adapt the script for your allocation size, walltime, modules and cluster architecture.
   - Adapt the `flux-config.toml` file in `conf.d/` to your needs and pass it to the `flux start` command using the `--config` option.
3. **Use Cases**
    1. **Resource Allocation Type**
        - The `alloc_type.py` CLI Plugin introduces a new option on the flux submit command family: `--alloc-type`.
        - This option allows users to specify `compact` or  `spread`
        allocation strategies when submitting jobs to Flux.
        - `compact` tries to fill each node completely before moving to the next one.
        - `spread` does half socket allocation.
        - **Usage**: `flux run -n <ntasks> --alloc-type=[compact|spread] <script>`
    2. **Co-scheduling queue**
        - The `cosched.py` CLI Plugin allows you to define a co-scheduling queue in Flux.
        - Each job submitted to this queue will run with spread allocation.
        - **Usage**: `flux run -n <ntasks> --cosched <script>`
        - `flux-config.queues.toml` and  `R.queues.template` located in `conf.d` define the partition for this use case. 
    3. **Moldability**
        - A custom flux-sched version that supports job moldability in Flux.
        - The user can specify different task count options and complementary wall times for each job.
        - **Example Usage**: `flux run -S task_counts="[3,2,1]" -S durations="[1,2,3]" hostname`.
        - Flux will dynamically choose a task_counts[i], durations[i] pair just before job execution.
        - `flux-config.moldability.toml` enforces the moldability support.
        - Currently only compact allocation is supported in this use case.
4. **Example Scripts**
   The `examples/` folder contains examples of the above use cases.
    ```bash
   cd flurm/aris/scripts/examples
   make
   sbatch <example script>.sh 
   ```
6. **Evaluation**
   The scripts used for evaluating the allocation strategies and co-scheduling capabilities of Flux on ARIS can be found in the `eval/` folder.
   You need to have NAS benchmarks installed and configured accordingly.
4. **Monitor and Clean Up**
   - Use the `check_ghosts.sh` script to check for and clean up any leftover Flux or Slurm processes that may not have terminated properly after your jobs complete. Ghost processes should be impossible if everything works correctly, but this script is useful for debugging.

## Notes

- The provided scripts and configurations are tailored for the ARIS HPC system, e.g. they assume every compute node has 2 sockets and 10 cores per socket. You may need to adjust them for other systems.
- For more information on Flux and its capabilities, refer to the [Flux documentation](https://flux-framework.readthedocs.io/en/latest/).
