#!/bin/bash

set -e
set -x
set -o pipefail

DEBIAN_FRONTEND=noninteractive apt-get update && \
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
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
