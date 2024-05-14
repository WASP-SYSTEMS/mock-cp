#!/bin/bash

set -e

# if LOCAL_USER is set to something other than root ...
if [[ -n "${LOCAL_USER}" ]] && [[ "${LOCAL_USER}" != "0:0" ]]; then

    # extract user and group from the variable
    LOCAL_USER_ID=${LOCAL_USER%:*}
    LOCAL_USER_GID=${LOCAL_USER#*:}

    # create the user aixcc with user ID and group ID of the caller
    mkdir -p /home/aixcc
    groupadd -o -g "${LOCAL_USER_GID}" aixcc 2> /dev/null
    useradd -o -m -g "${LOCAL_USER_GID}" -u "${LOCAL_USER_ID}" -d /home/aixcc aixcc 2> /dev/null
    export HOME=/home/aixcc
    # shellcheck disable=SC2086
    chown -R ${LOCAL_USER} ${HOME}

    # Add aixcc user as sudoer without password
    echo "aixcc ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers.d/user

    # set output directories to be owned by the user
    # shellcheck disable=SC2086
    chown -R ${LOCAL_USER} "${WORK}" "${OUT}"

    # run the passed command and user aixcc
    # shellcheck disable=SC2086
    exec gosu ${LOCAL_USER} "$@"
else # run command as is as root
    exec "$@"
fi
