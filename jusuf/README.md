# Flurm on JUSUF

This directory contains the JUSUF setup for running Flux inside a Slurm allocation. It supports both upstream Flux packages and custom `flux-core`/`flux-sched` source releases installed with Spack.

The custom installation workflow was developed with Spack `1.3.0.dev0`.

## Files

| File | Purpose |
| --- | --- |
| `opt/install_flux_base.sh` | Bootstrap Spack, install GCC 13, and install upstream `flux-sched@0.55.0` with its Core dependency. |
| `opt/install_flux_custom.sh` | Download, build, and install a custom Core/scheduler release pair. |
| `opt/configure_flux_recipes.py` | Generate custom recipe declarations; required beside the custom installer. |
| `scripts/flux_template.sh` | Example Slurm job using upstream Flux. |
| `scripts/flux_template_custom.sh` | Slurm job that loads a custom release pair and checks its Argilos configuration. |
| `scripts/test_custom_installation.sh` | Check Fluxion modules and the parsed Argilos values inside the broker. |
| `scripts/jgf_gen.py` | Generate the resource graph used by the templates. |
| `conf.d/flux-config.toml` | Upstream Flux broker configuration template. |
| `conf.d/flux-config-custom.toml` | Configuration for the custom flexible Argilos scheduler. |

## 1. Prepare the cluster directories

Run the commands in this section **on JUSUF**.

The scripts use two locations:

| Location | Contents |
| --- | --- |
| `$HOME/flurm` | This directory's scripts, configuration templates, and generated custom recipes. |
| `$PROJECT_seanergys/$USER/flurm` | Spack, its installation store/cache/staging area, custom environments, and generated job configurations. |

Clone the repository and expose its `jusuf/` directory at `$HOME/flurm`:

```bash
mkdir -p "$HOME/src"
git clone https://github.com/cslab-ntua/flurm.git "$HOME/src/flurm"
ln -s "$HOME/src/flurm/jusuf" "$HOME/flurm"
cd "$HOME/flurm"
```

Check the project variable before installing:

```bash
echo "$PROJECT_seanergys"
export FLURM_DIR="$PROJECT_seanergys/$USER/flurm"
mkdir -p "$FLURM_DIR"
```

## 2. Install upstream Flux and Spack

From `$HOME/flurm`, run:

```bash
bash opt/install_flux_base.sh
```

This installs GCC 13 and upstream `flux-sched@0.55.0%gcc@13`, including its dependencies. Custom Flux installation also uses this Spack/GCC setup, so **complete this step first**.

The base installer is for a fresh setup: it unconditionally clones Spack into `$FLURM_DIR/spack`. If that directory already exists, reuse it rather than rerunning the clone. To resume package installation:

```bash
export FLURM_DIR="$PROJECT_seanergys/$USER/flurm"
export SPACK_USER_CACHE_PATH="$FLURM_DIR/.spack"
export SPACK_USER_CONFIG_PATH="$FLURM_DIR/.spack"
export SPACK_STAGE="$FLURM_DIR/spack_stage"
source "$FLURM_DIR/spack/share/spack/setup-env.sh"

spack compiler find
spack install gcc@13
spack compiler find
spack install 'flux-sched@0.55.0%gcc@13'
```

Submit the template script to check that everything went well:

```bash
cd "$HOME/flurm"
sbatch scripts/flux_template.sh
```

The template generates a resource graph and R file, starts one broker per allocated node, and runs `hostname` on compute resources excluding the first/control node. Replace its final workload command for your application.

## 3. Publish custom Flux source releases

Do this **on your development machine**, in your modified Core and scheduler checkouts. These are source releases: Spack downloads and compiles them on JUSUF.

Choose a version for each repository based on its actual upstream base. Core and scheduler version numbers are independent. For example:

```text
Core:      0.85.0-cosched
Scheduler: 0.53-moldable-config
```

Commit the intended changes before creating each tag. In your Core checkout:

```bash
CORE_VERSION=0.85.0-cosched
git status
git tag -a "v$CORE_VERSION" -m "Custom Core $CORE_VERSION"
git push origin HEAD
git push origin "v$CORE_VERSION"
git archive --format=tar.gz \
    --prefix="flux-core-$CORE_VERSION/" \
    --output="../flux-core-$CORE_VERSION.tar.gz" \
    "v$CORE_VERSION"
sha256sum "../flux-core-$CORE_VERSION.tar.gz"
```

In your scheduler checkout:

```bash
SCHED_VERSION=0.53-moldable-config
git status
git tag -a "v$SCHED_VERSION" -m "Custom scheduler $SCHED_VERSION"
git push origin HEAD
git push origin "v$SCHED_VERSION"
git archive --format=tar.gz \
    --prefix="flux-sched-$SCHED_VERSION/" \
    --output="../flux-sched-$SCHED_VERSION.tar.gz" \
    "v$SCHED_VERSION"
sha256sum "../flux-sched-$SCHED_VERSION.tar.gz"
```

Use the remote that points to your fork if it is not `origin`. `git archive` includes tracked files at the tag, not uncommitted/untracked files or submodule contents. If your sources use submodules, prepare an archive that includes their required contents instead.

In each GitHub repository, create a Release from the tag and upload the corresponding `.tar.gz` as a release asset. Save its direct download URL and the SHA-256 of that exact uploaded file. The cluster must be able to download the assets; private repositories need authentication configured separately.

## 4. Install a custom release pair on JUSUF

From `$HOME/flurm`, run the following example with the URLs and checksums of the releases you want:

```bash
bash opt/install_flux_custom.sh \
  --core-version 'v0.85.0-cosched' \
  --core-url 'https://github.com/cslab-ntua/flux-core/releases/download/v0.85.0-cosched/flux-core-0.85.0-cosched.tar.gz' \
  --core-sha256 '4d06fcfc199be42a5595327b226eb247bfc939e29349dc20d2e3acf74a3fadd5' \
  --sched-version 'v0.53-moldable-config' \
  --sched-url 'https://github.com/cslab-ntua/flux-sched/releases/download/v0.53-moldable-config/flux-sched-0.53-moldable-config.tar.gz' \
  --sched-sha256 'ed61094f359b2c8be3b9d88f5d2081c79a954375e8b2da22b9bcd33d1e612568'
```

A leading `v` in versions and a `sha256:` prefix on checksums are optional.

The installer:

1. Creates `$HOME/flurm/custom-flux-packages/spack_repo/customflux`.
2. Copies the builtin Core/scheduler recipes and their patch files.
3. Adds your release URLs, checksums, bootstrap dependencies, and an exact scheduler-to-Core dependency.
4. Registers the `customflux` repository in the project-local Spack user configuration.
5. Creates or reuses an environment for the release pair, concretizes it, and builds the packages with GCC 13.
6. Writes an environment loader and checks the installed Core version.

For the example, load the result in your job script with:

```bash
source "$PROJECT_seanergys/$USER/flurm/custom-flux-envs/core-0.85.0-cosched_sched-0.53-moldable-config_gcc13/load.sh"
flux version
```

Always use the generated loader for custom jobs. It also exposes the scheduler's modprobe configuration so the broker starts Fluxion from its separate installation prefix. Executing the installer does **not** load Flux into the parent shell.

To test basic execution, append `--smoke-test` to the installation command **inside a suitable compute allocation**. It checks the resource/qmanager modules and runs `hostname`. Installation without that option does not start a test broker.

## 5. Test Argilos configuration under Slurm

The custom template is a specific test for the flexible Argilos implementation, not a generic smoke test for every Flux fork. It uses `conf.d/flux-config-custom.toml`, which selects `flexible_argilos`, enables `emit-nslots`, and sets `sched-fluxion-resource.argilos.b = 8.0`.

Submit the installed release pair:

```bash
cd "$HOME/flurm"
sbatch scripts/flux_template_custom.sh \
    0.85.0-cosched 0.53-moldable-config
```

The template defaults to those versions and a 120-second check timeout.

The check runs once as the broker's initial program. It waits for both Fluxion modules, checks the active Argilos table/traverser, and searches `flux dmesg` for the parsed parameter values. It prints a PASS message on success and exits nonzero with diagnostics on failure.

The job prints the log directory, under:

```text
$PROJECT_seanergys/$USER/flurm/conf.d/<unique-run-id>/installation-check/
```

This contains `modules.txt`, `config.json`, `argilos-config.json`, `dmesg.log`, `argilos-match.txt`, and, after successful scheduler checks, `cli-plugins.txt`. Logs from failed broker startup may appear only in the Slurm error file because the check script has not started yet.

## 6. Install another custom version

Publish a new tag/archive, calculate its checksum, and rerun `install_flux_custom.sh` with the new metadata. Previous release declarations and installations are retained; repeating the same release pair reuses its environment.

Published versions are immutable in this workflow. Changing an existing version's URL, checksum, or scheduler-to-Core dependency is rejected. Use a new custom version instead. A new scheduler version can reuse an existing custom Core release if Core has not changed.

## Troubleshooting

- **`Stages/2026` remains after `module purge`:** this message alone does not indicate a Flux failure. Read the subsequent error or exit status.
- **Spack clone already exists:** reuse the existing installation; the base bootstrap script does not skip its clone step.
