#!/bin/bash

set -eo pipefail

usage() {
    cat <<'EOF'
Usage: install_flux_custom.sh \
  --core-version VERSION --core-url URL --core-sha256 SHA256 \
  --sched-version VERSION --sched-url URL --sched-sha256 SHA256 [--smoke-test]

Build and install custom Flux releases using the existing Spack and GCC 13 setup.
VERSION is the Spack version (for example, 0.85.0-cosched or 0.53-moldable-config).
An optional leading v and optional sha256: checksum prefix are accepted and stripped.
URL is the full release asset URL, including its GitHub tag.
Registers the recipes and creates or reuses a separate environment per release pair.
Earlier release declarations and installations are retained.
--smoke-test also starts a local Flux instance and runs hostname; use in an allocation.
EOF
}

CORE_VERSION= CORE_URL= CORE_SHA256=
SCHED_VERSION= SCHED_URL= SCHED_SHA256=
SMOKE_TEST=false
while (( $# )); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --smoke-test) SMOKE_TEST=true; shift ;;
        --core-version|--core-url|--core-sha256|--sched-version|--sched-url|--sched-sha256)
            if (( $# < 2 )) || [[ -z "$2" || "$2" == --* ]]; then
                printf 'Missing value for %s\n' "$1" >&2
                exit 2
            fi
            case "$1" in
                --core-version) CORE_VERSION="$2" ;;
                --core-url) CORE_URL="$2" ;;
                --core-sha256) CORE_SHA256="$2" ;;
                --sched-version) SCHED_VERSION="$2" ;;
                --sched-url) SCHED_URL="$2" ;;
                --sched-sha256) SCHED_SHA256="$2" ;;
            esac
            shift 2 ;;
        *) printf 'Unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
done

if [[ -z "$CORE_VERSION" || -z "$CORE_URL" || -z "$CORE_SHA256" ||
      -z "$SCHED_VERSION" || -z "$SCHED_URL" || -z "$SCHED_SHA256" ]]; then
    usage >&2
    exit 2
fi
CORE_VERSION="${CORE_VERSION#v}"
SCHED_VERSION="${SCHED_VERSION#v}"
CORE_SHA256="${CORE_SHA256#sha256:}"
SCHED_SHA256="${SCHED_SHA256#sha256:}"

for version in "$CORE_VERSION" "$SCHED_VERSION"; do
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)*(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; then
        printf 'Expected a release version such as 0.85.0-cosched or 0.53-moldable-config, got: %s\n' "$version" >&2
        exit 2
    fi
done
for checksum in "$CORE_SHA256" "$SCHED_SHA256"; do
    if [[ ! "$checksum" =~ ^[[:xdigit:]]{64}$ ]]; then
        printf 'Each SHA-256 must contain exactly 64 hexadecimal characters.\n' >&2
        exit 2
    fi
done
for url in "$CORE_URL" "$SCHED_URL"; do
    if [[ "$url" != https://* || "$url" == *[[:space:]]* ]]; then
        printf 'Expected an HTTPS release asset URL, got: %s\n' "$url" >&2
        exit 2
    fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
: "${PROJECT_seanergys:?PROJECT_seanergys is not set}"
: "${USER:?USER is not set}"

module purge

FLURM_DIR="$PROJECT_seanergys/$USER/flurm"
cd "$FLURM_DIR"

export SPACK_USER_CACHE_PATH="$FLURM_DIR/.spack"
export SPACK_USER_CONFIG_PATH="$FLURM_DIR/.spack"
export SPACK_STAGE="$FLURM_DIR/spack_stage"

source "$FLURM_DIR/spack/share/spack/setup-env.sh"

if [[ -n "${SPACK_ENV:-}" ]]; then
    spack env deactivate
fi
if [[ -n "${SPACK_LOADED_HASHES:-}" ]]; then
    spack unload --all
fi

spack --version

HOME_FLURM_DIR="$HOME/flurm"
CUSTOM_REPO_ROOT="$HOME_FLURM_DIR/custom-flux-packages"
CUSTOM_REPO="$CUSTOM_REPO_ROOT/spack_repo/customflux"

if [[ ! -f "$CUSTOM_REPO/repo.yaml" ]]; then
    spack repo create "$CUSTOM_REPO_ROOT" customflux
fi

CORE_RECIPE_DIR="$(spack location -p builtin.flux-core)"
SCHED_RECIPE_DIR="$(spack location -p builtin.flux-sched)"

if [[ ! -d "$CUSTOM_REPO/packages/flux_core" ]]; then
    cp -a "$CORE_RECIPE_DIR" "$CUSTOM_REPO/packages/flux_core"
fi
if [[ ! -d "$CUSTOM_REPO/packages/flux_sched" ]]; then
    cp -a "$SCHED_RECIPE_DIR" "$CUSTOM_REPO/packages/flux_sched"
fi

spack python "$SCRIPT_DIR/configure_flux_recipes.py" \
    --repo "$CUSTOM_REPO" \
    --core-version "$CORE_VERSION" --core-url "$CORE_URL" --core-sha256 "$CORE_SHA256" \
    --sched-version "$SCHED_VERSION" --sched-url "$SCHED_URL" --sched-sha256 "$SCHED_SHA256"

printf 'Custom recipes are ready in: %s\n' "$CUSTOM_REPO/packages"

REGISTERED_REPO="$(spack python -c 'import spack.config; print((spack.config.CONFIG.get("repos", scope="user") or {}).get("customflux", ""))')"
if [[ -z "$REGISTERED_REPO" ]]; then
    spack repo add --scope=user --name customflux "$CUSTOM_REPO"
elif [[ "$REGISTERED_REPO" != "$CUSTOM_REPO" ]]; then
    printf 'The user repository customflux already points to %s; expected %s.\n' \
        "$REGISTERED_REPO" "$CUSTOM_REPO" >&2
    exit 1
fi

ENV_DIR="$FLURM_DIR/custom-flux-envs/core-${CORE_VERSION}_sched-${SCHED_VERSION}_gcc13"
SCHED_SPEC="customflux.flux-sched@=${SCHED_VERSION}%gcc@13"
CORE_SPEC="customflux.flux-core@=${CORE_VERSION}%gcc@13"

mkdir -p "$(dirname -- "$ENV_DIR")"
if [[ ! -f "$ENV_DIR/spack.yaml" ]]; then
    spack env create --without-view -d "$ENV_DIR"
fi
spack env activate --without-view "$ENV_DIR"
spack config --scope="env:$ENV_DIR" add 'concretizer:unify:true'
spack add "$SCHED_SPEC ^$CORE_SPEC"
spack concretize
spack spec -N -l
spack install --yes-to-all
SCHED_PREFIX="$(spack location -i "$SCHED_SPEC")"

# Loading in an executed script does not change the caller's shell. Write a loader
# with the same configuration paths for interactive use and batch job scripts.
LOAD_SCRIPT="$ENV_DIR/load.sh"
{
    printf '# Source this file to load this custom Flux installation.\n'
    printf 'export SPACK_USER_CACHE_PATH=%q\n' "$SPACK_USER_CACHE_PATH"
    printf 'export SPACK_USER_CONFIG_PATH=%q\n' "$SPACK_USER_CONFIG_PATH"
    printf 'export SPACK_STAGE=%q\n' "$SPACK_STAGE"
    printf 'source %q\n' "$FLURM_DIR/spack/share/spack/setup-env.sh"
    printf 'if [[ -n "${SPACK_ENV:-}" ]]; then spack env deactivate; fi\n'
    printf 'if [[ -n "${SPACK_LOADED_HASHES:-}" ]]; then spack unload --all; fi\n'
    printf 'spack env activate --without-view %q\n' "$ENV_DIR"
    printf 'spack load %q\n' "$SCHED_SPEC"
    # Core 0.85+ uses modprobe startup files. The builtin scheduler recipe only
    # exposes the legacy FLUX_RC_EXTRA path, so add the separate scheduler prefix.
    # Restore the caller's original append path on repeat loads/version switches.
    printf 'if [[ -n "${CUSTOM_FLUX_MODPROBE_PATH_SAVED+x}" ]]; then\n'
    printf '    export FLUX_MODPROBE_PATH_APPEND="$CUSTOM_FLUX_MODPROBE_PATH_SAVED"\n'
    printf 'fi\n'
    printf 'export CUSTOM_FLUX_MODPROBE_PATH_SAVED="${FLUX_MODPROBE_PATH_APPEND:-}"\n'
    if [[ -d "$SCHED_PREFIX/etc/flux/modprobe" ]]; then
        printf 'export FLUX_MODPROBE_PATH_APPEND="${FLUX_MODPROBE_PATH_APPEND:+${FLUX_MODPROBE_PATH_APPEND}:}"%q\n' \
            "$SCHED_PREFIX/etc/flux/modprobe"
    fi
} > "$LOAD_SCRIPT"

source "$LOAD_SCRIPT"
spack find -dlv
spack location -i "$CORE_SPEC"
spack location -i "$SCHED_SPEC"
command -v flux
flux version

if "$SMOKE_TEST"; then
    flux start -- sh -ec '
        trap '\''status=$?; if [ "$status" -ne 0 ]; then flux dmesg >&2 || :; fi'\'' EXIT
        modules=$(flux module list)
        printf "%s\n" "$modules"
        for module in sched-fluxion-resource sched-fluxion-qmanager; do
            if ! printf "%s\n" "$modules" | grep -q "$module"; then
                printf "Fluxion startup failed: %s is not loaded.\n" "$module" >&2
                exit 1
            fi
        done
        flux run -n 1 hostname
    '
fi

printf '\nInstallation complete. To load it in your shell or job script:\n'
printf 'source %q\n' "$LOAD_SCRIPT"

