#!/usr/bin/env bash

# get directory containing the script
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
SCRIPT_FILE="$(basename "${BASH_SOURCE[0]}")"

# print warning/error
warn() {
    echo "$*" >&2
}

# kill the script with an error message
die() {
    warn "$*"
    exit 1
}

#################################
## Script Variables
#################################

# these directories are shared with the docker container
WORK="${SCRIPT_DIR}/work"
SRC="${SCRIPT_DIR}/src"
OUT="${SCRIPT_DIR}/out"

# extra arguments passed to git apply
: "${PATCH_EXTRA_ARGS:=}"

# Load project defaults from environment file
CP_ENV_FILE="${SCRIPT_DIR}/.env.project"
[[ -f "${CP_ENV_FILE}" ]] || die "Missing required environment variable file: ${CP_ENV_FILE}"
# shellcheck source=/dev/null
source "${CP_ENV_FILE}"

# Setup docker environment file if exists
: "${DOCKER_ENV_ARGS:=}"
: "${DOCKER_RUN_ENV_FILE:="${SCRIPT_DIR}/.env.docker"}"
if [[ -z "${DOCKER_ENV_ARGS}" ]] && [[ -n "${DOCKER_RUN_ENV_FILE}" ]] && [[ -f "${DOCKER_RUN_ENV_FILE}" ]]; then
    DOCKER_ENV_ARGS="--env-file ${DOCKER_RUN_ENV_FILE}"
fi

# setup docker volume args
: "${DOCKER_VOL_ARGS:="-v ${WORK}:/work -v ${SRC}:/src -v ${OUT}:/out"}"

# setup extra args that can be specified
: "${DOCKER_EXTRA_ARGS:=}"
if [[ -n "${CP_DOCKER_EXTRA_ARGS}" ]]; then
    DOCKER_EXTRA_ARGS+=" ${CP_DOCKER_EXTRA_ARGS}"
fi

# verify if the needed docker image variable is set
CP_DOCKER_IMAGE=$(yq  -r '.docker_image' "${SCRIPT_DIR}/project.yaml" 2>/dev/null || echo "")
: "${DOCKER_IMAGE_NAME:=${CP_DOCKER_IMAGE}}"
[[ -n "${DOCKER_IMAGE_NAME}" ]] || warn "WARNING: environment variable DOCKER_IMAGE_NAME is not set"

# pass through calling user to Docker container
: "${DOCKER_USER_ARGS:="-e LOCAL_USER=$(id -u):$(id -g)"}"

#################################
## Utility functions
#################################

print_usage() {
    warn "A helper script for CP interactions."
    warn
    warn "Usage: ${SCRIPT_FILE} build|run_pov|run_test|custom"
    warn
    warn "Subcommands:"
    warn "  build [<patch_file> <source>]       Build the CP (an optional patch file for a given source repo can be supplied)"
    warn "  run_pov <blob_file> <harness_name>  Run the binary data blob against specified harness"
    warn "  run_tests                           Run functionality tests"
    warn "  custom <arbitrary cmd ...>          Run an arbitrary command in the docker container"
    die
}

check_docker_image() {
    docker inspect "${DOCKER_IMAGE_NAME}" &> /dev/null \
        || die "Requested docker image not found: ${DOCKER_IMAGE_NAME};" \
               "see README.md to obtain or build a docker container."
}

docker_run_cmd_setup_steps() {
    # create/verify shared directories
    mkdir -p "${WORK}" "${OUT}" || die "Failed to create needed shared directories"
    [[ -d "${SRC}" ]] || die "Missing source directory: ${SRC}"

    # ensure the needed docker image is present
    check_docker_image
}

# generic wrapper/handler for all calls to "docker run", script exits here
docker_run_generic() {
    local output_cmd_dir="$1"
    local _status
    local _cid
    shift

    # create the output directory if it doesn't exist, or default to ${OUT}
    if [[ ! -d "${output_cmd_dir}" ]]; then
        mkdir -p "${output_cmd_dir}" || output_cmd_dir="${OUT}"
    fi

    # delete the container ID file if it exists (can't be reused)
    [[ -f "${output_cmd_dir}/docker.cid" ]] && \
        rm -rf "${output_cmd_dir}/docker.cid"

    # call "docker run" with the set environment variables and passed args
    # shellcheck disable=SC2086
    docker run \
        --cidfile "${output_cmd_dir}/docker.cid" \
        ${DOCKER_VOL_ARGS} \
        ${DOCKER_ENV_ARGS} \
        ${DOCKER_USER_ARGS} \
        ${DOCKER_EXTRA_ARGS} \
        ${DOCKER_IMAGE_NAME} \
        "$@"

    # preserve exit code from "docker run"
    _status=$?

    # absence of docker.cid implies "docker run" failed so just exit
    # with the direct exit code from "docker run" (like w/ status >= 125)
    if [[ ! -f "${output_cmd_dir}/docker.cid" ]]; then
        warn "Docker run failed to execute, returned status: ${_status}"
        exit ${_status}
    fi

    # from here, docker.cid exists so preserve the docker logs and exit code
    # if the container is not running anymore

    # obtain contained ID
    _cid="$(cat "${output_cmd_dir}/docker.cid")"

    # record the container logs if the output directory exists
    if [[ -d "${output_cmd_dir}" ]]; then
        docker logs --details "${_cid}" \
            > "${output_cmd_dir}/stdout.log" \
            2> "${output_cmd_dir}/stderr.log"
    fi

    # if the container is still running, then don't look for an exit code
    # and leave it alone
    if [[ $(docker inspect -f '{{.State.Running}}' "${_cid}") == "true" ]];
        then echo "Container is still running: ${_cid}";
    else # container is not running
        # record the exit code if the output directory exists
        exitcode=$(docker inspect -f '{{.State.ExitCode}}' "${_cid}")
        if [[ -d "${output_cmd_dir}" ]]; then
            echo -n "${exitcode}" > "${output_cmd_dir}/exitcode"
        else
            echo "docker run exit code: ${exitcode}"
        fi
        # cleanup the anonymous volumes of the stopped container
        docker rm -v "${_cid}" > /dev/null 2>&1 || true
    fi

    # exit this script with 0 if "docker run" did execute - the preserved
    # exit code from "docker run" is in ${output_cmd_dir}/exitcode
    exit 0
}

# create an output directory in ${OUT}/output/<timestamp>--cmd
create_output_directory() {
    local tmp_out_dir

    tmp_out_dir="${OUT}/output/$(date +"%s.%N" --utc)--$1"

    mkdir -p "${tmp_out_dir}" || { warn "WARNING: failed to create command output directory: ${tmp_out_dir}"; echo ""; }

    echo "${tmp_out_dir}"
}

# "build" command handler
build() {
    shift

    # do sanity checks before calling docker run
    docker_run_cmd_setup_steps

    ##### Run patch command if patch file was supplied #####

    if [ -n "$1" ]; then
        if [ -z "$2" ]; then
            warn "Error: Must supply source repo name along with patch file!"
            print_usage
        fi

        PATCH_FILE=$1
        SOURCE_TARGET=$2

        if [ ! -d "${SRC}/${SOURCE_TARGET}" ]; then
            warn "Source repository not found: ${SRC}/${SOURCE_TARGET}"
            die
        fi

        # check validity of patch file provided
        PATCH_FILE=$(realpath "${PATCH_FILE}")
        [[ -f "${PATCH_FILE}" ]] || die "Patch file not found: ${PATCH_FILE}"

        # apply patch
        # shellcheck disable=SC2086
        git -C "${SRC}/${SOURCE_TARGET}" apply \
            ${PATCH_EXTRA_ARGS} \
            "${PATCH_FILE}" || die "Patching failed using: ${PATCH_FILE}"
    fi

    ##### Build source within docker container #####

    docker_run_generic \
        "$(create_output_directory "build")" \
        "cmd_harness.sh" "build"
}

# "run_pov" command handler
run_pov() {
    shift

    # do sanity checks before calling docker run
    docker_run_cmd_setup_steps

    ##### Copy blob file to work directory #####

    BLOB_FILE=$1
    HARNESS_ID=$2
    cp "$BLOB_FILE" "${WORK}/tmp_blob" \
        || die "No blob file found!"

    ##### Run PoV within docker container, output sanitizer information #####

    docker_run_generic \
        "$(create_output_directory "run_pov")" \
        "cmd_harness.sh" "pov" "/work/tmp_blob" "/out/${HARNESS_ID}"
}

# "run_tests" command handler
run_tests() {
    shift

    # do sanity checks before calling docker run
    docker_run_cmd_setup_steps

    ##### Run tests within docker container, output test results #####

    docker_run_generic \
        "$(create_output_directory "run_tests")" \
        "cmd_harness.sh" "tests"
}

# choose your own adventure with an arbitrary docker run command invocation
custom() {
    shift

    # do sanity checks before calling docker run
    docker_run_cmd_setup_steps

    ##### Run arbitrary command within the docker container #####
    docker_run_generic \
        "$(create_output_directory "custom")" \
        "$@"
}

# array of top-level command handlers
declare -A MAIN_COMMANDS=(
    [help]=print_usage
    [build]=build
    [run_pov]=run_pov
    [run_tests]=run_tests
    [custom]=custom
)

#################################
## Main script code starts here
#################################

# look for needed commands/dependencies
REQUIRED_COMMANDS="git docker rsync"
for c in ${REQUIRED_COMMANDS}; do
    command -v "${c}" >/dev/null || warn "WARNING: needed executable (${c}) not found in PATH"
done

# call subcommand function from declared array of handlers (default to help)
"${MAIN_COMMANDS[${1:-help}]:-${MAIN_COMMANDS[help]}}" "$@"
