# Mock Challenge Project 

This repository represents a minimal sample AIxCC ASC Challenge Project.

## Using this repository

This repository is meant to be used as a minimal Challenge Project Exemplar for testing CRSs and CI/CD integration.

## What's in this repository

`src/` - this directory is where CP source code is loaded, analyzed, and built from.

`out/` - this directory is used to store artifacts generated from the docker containers.

`work/` - this directory is used to store temporary or intermediate artifacts passed to and from containers.

`container_scripts/` - this directory contains scripts used in the Docker container to process requested operations form `run.sh`.

`includes/` - directory that holds target-specific Makefiles.

`run.sh` - a script that provides a CRS with a standardized interface to interact with the challenge project.

`project.yaml` - a yaml document detailing many important aspects of the challenge project.

`Dockerfile` - the Dockerfile used to create the CP docker image for building, running, testing.

`.env.project` - CP-specific environment variables used for configuration.

`.env.docker` - Default environment variables file passed to running docker containers.

`Makefile` - top-level Makefile for development-related targets.

## Setup

Prior to evaluating a CP that is specified in this repo, there are a number of
dependencies and initial steps that should be taken.

First, to use this repository in a development (pre-game) environment, the
following dependencies are required. Note, the tested (default) operating system is
Ubuntu 22.04.

```bash
- docker >= 24.0.5
- GNU make >= 4.3
- yq >= 4
```

Prior to using `run.sh`, the CP source code repositories specified in the
`project.yaml` file must be obtained. Assuming the proper repository access
tokens are in place, the code will be cloned into `./src` by invoking the
following command:

```bash
make cpsrc-prepare
```

Additionally, the CP repositories can be removed using the make command, which
deletes the folders:

```bash
make cpsrc-clean
```

In addition to the CP source, executing `run.sh` requires the appropriate
Docker image for the CP. Various Makefile targets detailed below will help
in obtaining a valid Docker image for the CP.

Run the following command to pull down the CP-specific Docker image specified
in the `project.yaml` file. Note, the other Docker-specific Makefile targets can
be ignored when using the published image specified in `project.yaml`.

```bash
make docker-pull
```

Another option is to build the CP-specific Docker image locally using the CP
source and the included `Dockerfile`. The following command will initiate the
build process. Note, for the following commands, the environment variable
`DOCKER_IMAGE_NAME` may be specified as an environment variable to assign a
specific name to the locally built docker image. The default value of
`DOCKER_IMAGE_NAME` is derived from the Docker image name in `project.yaml`.

```bash
make docker-build
```

The following command will add an environment variable entry for
`DOCKER_IMAGE_NAME` to `.env.project` such that calls to `run.sh` will use the
locally built docker image by default.

```bash
make docker-config-local
```

Lastly, the following command will delete the docker image specified with
|`DOCKER_IMAGE_NAME` from the local host and remove any mention of it from
`.env.project`. Note, this command will not remove the CP-specific docker image
(from `.project.yaml`) unless `DOCKER_IMAGE_NAME` was explicitly set to that
name (which is unexpected and not recommended).

```bash
make docker-clean
```

## Usage

The included `run.sh` script is the primary mechanism to build and test the CP.
The usage output with example commands is included below.

```bash
A helper script for CP interactions.

Usage: run.sh build|run_pov|run_test|custom

Subcommands:
  build [<patch_file> <source>]       Build the CP (an optional patch file for a given source repo can be supplied)
  run_pov <blob_file> <harness_name>  Run the binary data blob against specified harness
  run_tests                           Run functionality tests
  custom                              Run an arbitrary command in the docker container
```

Each subcommand in `run.sh` ultimately results in an invocation of `docker run`
using the various environment variables that `run.sh` supports and supplied
from `.env.project` and `.env.docker`.

The `run.sh` script can exit prior to invoking `docker run` due to some error
in usage or configuration. Such an error will result in an exit code of 1 being
returned directly to the caller.

Assuming no preceding errors, `run.sh` will exit after the call to `docker run`
returns, regardless of the state of the target docker container. The `run.sh`
script will return 0 if the container was launched and has internal state to
report on. Otherwise, the exit code reflects the error code obtained from the
failed invocation of `docker run`.

The output obtained from a Docker container must be inspected to determine
success or failure of the specified command. The `run.sh` script records the
logs, ID, and exit code (if any), from all invocations of `docker run` in the
folder `out/output`. The per invocation data will be found in subfolders with
the naming scheme `<timestamp>--<subcommand>`, where `<timestamp>` is of the
format `<seconds>.<nanoseconds>` from UTC and `<subcommand>` is the first
argument passed to `run.sh`.

The contents of the subfolders (`out/output/<timestamp>--<subcommand>`) include:

- `docker.cid`: Container ID recorded using the `--cidfile` option
  to `docker run`

- `stdout.log`: stdout output from docker container

- `stderr.log`: stderr output from docker container

- `exitcode`: The exit code from the command in the docker container

The `stdout.log` and `stderr.log` files will be useful to determine if
certain scenarios occurred such as a sanitizer getting triggered as a result
of `./run.sh run_pov ...`. The `exitcode` contents will be important for
determining general success or failure of commands. The `docker.cid` file
is only useful for tracking / housekeeping of docker artifacts and is not
expected to be all that useful to a CRS.

For almost all cases, a CRS should expect to see all four files from a
successful invocation of `docker run` in the `run.sh` script. The one expected
exception is `exitcode` will be missing if the container is still running.
This may occur if `run.sh` is invoked with options such as
`DOCKER_EXTRA_ARGS="-d"`.

## Sample Usage

The below sample usage mirrors what the challenge evaluator does in
the challenge project verification pipeline

```
make cpsrc-prepare
make docker-build
make docker-config-local

./run.sh build

./run.sh run_tests

./run.sh run_pov exemplar_only/cpv_1/blobs/sample_solve.bin stdin_harness.sh
./run.sh run_pov exemplar_only/cpv_2/blobs/sample_solve.bin stdin_harness.sh

./run.sh build exemplar_only/cpv_1/patches/samples/good_patch.diff /samples
./run.sh run_pov exemplar_only/cpv_1/blobs/sample_solve.bin stdin_harness.sh
./run.sh run_tests

git -C src/samples reset --hard HEAD
./run.sh build exemplar_only/cpv_2/patches/samples/good_patch.diff /samples
./run.sh run_pov exemplar_only/cpv_2/blobs/sample_solve.bin stdin_harness.sh
./run.sh run_tests

git -C src/samples reset --hard HEAD
./run.sh build exemplar_only/cpv_1/patches/samples/bad_patch.diff /samples
./run.sh run_pov exemplar_only/cpv_1/blobs/sample_solve.bin stdin_harness.sh
./run.sh run_tests

git -C src/samples reset --hard HEAD
./run.sh build exemplar_only/cpv_2/patches/samples/bad_patch.diff /samples
./run.sh run_pov exemplar_only/cpv_2/blobs/sample_solve.bin stdin_harness.sh
```
