#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026- European Centre for Medium-Range Weather Forecasts (ECMWF)
# SPDX-License-Identifier: Apache-2.0

set -e

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_directory="$(cd -- "$script_directory/.." && pwd)"

usage() {
    printf 'Usage: %s --preset PRESET [arguments...]\n' "$script_directory/${action}.sh" >&2
    if command -v jq >/dev/null 2>&1; then
        printf '\nAvailable presets:\n' >&2
        jq -r '.configurePresets[] | select(.hidden != true) | "  " + .name' \
            "$repository_directory/CMakePresets.json" >&2
    else
        printf '\nInstall jq to list the available presets.\n' >&2
    fi
}

action="${1:-}"
case "$action" in
    configure|build|test|workflow) shift ;;
    *) printf 'Usage: %s {configure|build|test|workflow} --preset PRESET [arguments...]\n' "$0" >&2; exit 2 ;;
esac

preset=""
arguments=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --preset|--preset=*)
            if [[ -n "$preset" ]]; then
                printf '%s\n' 'Specify --preset only once.' >&2
                usage
                exit 2
            fi
            if [[ "$1" == --preset ]]; then
                if [[ $# -lt 2 || -z "$2" || "$2" == -* ]]; then
                    printf '%s\n' '--preset requires a name.' >&2
                    usage
                    exit 2
                fi
                preset="$2"
                shift 2
            else
                preset="${1#--preset=}"
                shift
                if [[ -z "$preset" ]]; then
                    printf '%s\n' '--preset requires a name.' >&2
                    usage
                    exit 2
                fi
            fi
            ;;
        --)
            shift
            arguments+=("$@")
            break
            ;;
        *) arguments+=("$1"); shift ;;
    esac
done
if [[ -z "$preset" ]]; then
    printf '%s\n' 'The --preset argument is required.' >&2
    usage
    exit 2
fi
set -- "${arguments[@]}"

cd -- "$repository_directory"
if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' 'The preset helper requires jq to read CMakePresets.json.' >&2
    exit 2
fi
if ! preset_metadata=$(jq -ce --arg preset "$preset" '
    [.configurePresets[] | select(.name == $preset and .hidden != true)]
    | if length == 1 then .[0].vendor["ecmwf.int/gpu-aware-mpi/1.0"] else null end
    | select(type == "object")
    | select(.environmentFile | type == "string" and length > 0)
    ' CMakePresets.json); then
    printf 'Missing or invalid vendor metadata for preset: %s\n' "$preset" >&2
    exit 2
fi
environment_file=$(jq -r '.environmentFile' <<< "$preset_metadata")
test_launcher=()
if [[ "$action" == test || "$action" == workflow ]]; then
    if ! test_metadata=$(jq -ce --arg preset "$preset" '
        [.testPresets[] | select(.name == $preset and .hidden != true)]
        | if length == 1 then (.[0].vendor["ecmwf.int/gpu-aware-mpi/1.0"] // {}) else null end
        | select(type == "object")
        | select((.sallocArguments == null) or
            (.sallocArguments | type == "array" and all(.[]; type == "string" and length > 0 and (contains("\n") | not))))
        ' CMakePresets.json); then
        printf 'Missing test preset or invalid allocation metadata: %s\n' "$preset" >&2
        exit 2
    fi
    if jq -e '.sallocArguments != null' <<< "$test_metadata" >/dev/null; then
        test_launcher=(salloc)
        mapfile -t default_allocation_arguments < <(jq -r '.sallocArguments[]' <<< "$test_metadata")
        test_launcher+=("${default_allocation_arguments[@]}")
    fi
fi
if [[ ! -f "$environment_file" ]]; then
    printf 'Environment file not found: %s\n' "$environment_file" >&2
    exit 2
fi
source "$environment_file"

case "$action" in
    configure)
        exec cmake --preset "$preset" "$@"
        ;;
    build)
        exec cmake --build --preset "$preset" "$@"
        ;;
    workflow)
        if [[ -n "${SLURM_JOB_ID:-}" ]]; then
            exec cmake --workflow --preset "$preset" "$@"
        fi
        exec "${test_launcher[@]}" cmake --workflow --preset "$preset" "$@"
        ;;
    test)
        if [[ -n "${SLURM_JOB_ID:-}" ]]; then
            exec ctest --preset "$preset" "$@"
        fi
        exec "${test_launcher[@]}" ctest --preset "$preset" "$@"
        ;;
esac