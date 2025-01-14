# This Dockerfile will build an image that will provide an environment
# for the building, running, and testing of challenge project source.
#
# The base docker image is pre-built during the competition to
# support the pseudo-offline competition environment, as well
# as reducing time spent on dependency installations.
#
# Because of this, this Dockerfile will not be buildable at time
# of competition. It is simply for informational purposes.
#
# The location of the built base docker image can be found in the CP's
# project.yaml, as well as the .env.project file.
#
# Competitors are free to create their own docker images for use
# at their own discretion. No guarantees are made for custom images.
#
# To use a custom docker image with the run.sh script, modify
# the set the DOCKER_IMAGE_NAME environment variable:
#
#       DOCKER_IMAGE_NAME=my-custom-image ./run.sh

#################################################################
FROM gcr.io/oss-fuzz-base/base-clang as cp-sandbox-base

# global environment variables
ENV LC_ALL C.UTF-8
ENV LANG C.UTF-8
ENV TZ America/New_York
ENV USER root

# get common ubuntu packages that all containers must have, and
# setup gosu binary to modify user permissions in the container
RUN set -eux; \
    DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        gettext-base \
        gosu \
        sudo \
        && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    # verify that the binary works
    gosu nobody true

# $BINS = directory to store build and run scripts
# $SRC  = directory to store source code
# $OUT  = directory to store build artifacts (harnesses, test binaries)
# $WORK = directory to store intermediate files
ENV BINS=/usr/local/sbin/container_scripts
ENV SRC=/src
ENV OUT=/out
ENV WORK=/work
ENV LIB_FUZZING_ENGINE="/usr/lib/libFuzzingEngine.a"

# Create needed directories
RUN mkdir -p $OUT $WORK $SRC $BINS && chmod -R 0755 $OUT $WORK $SRC $BINS

# Add BINS directory to PATH
ENV PATH="$BINS:$PATH"

# Copy over the CP's container scripts directory
COPY --chmod=0755 ./container_scripts/* $BINS

# Install necessary dependencies for the image.
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends\
        binutils \
        build-essential \
        gcc \
        git \
        libelf-dev \
        make  \
        perl-base \
        rsync \
        && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

RUN cp /usr/local/lib/clang/18/lib/x86_64-unknown-linux-gnu/libclang_rt.fuzzer.a /usr/lib/libFuzzingEngine.a
RUN cp /usr/local/lib/clang/18/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a /usr/lib/libasan.a
    

# entrypoint uses gosu to set uid/gid (don't use $BINS in the
# path here -- docker build doesn't like that)
ENTRYPOINT ["/usr/local/sbin/container_scripts/entrypoint.sh"]

# set default working directory to ${WORK}
WORKDIR $WORK

