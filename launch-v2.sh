#!/bin/bash
#
# Copyright (c) 2020, NVIDIA CORPORATION.
# SPDX-License-Identifier: Apache-2.0

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

###############################################################################
#
# This is my $LOCAL_ENV file
#
LOCAL_ENV=.cheminf_local_environment-v2
#
###############################################################################

usage() {
    cat <<EOF

USAGE: launch.sh

launch utility script
----------------------------------------

launch.sh [command]

    valid commands:

    build
    pull
    push
    dev
    root
    jupyter


Getting Started tl;dr
----------------------------------------

    ./launch.sh build
    ./launch.sh dev
For more detailed info on getting started, see README.md


More Information
----------------------------------------

Note: This script looks for a file called $LOCAL_ENV in the
current directory. This file should define the following environment
variables:
    MEGAMOLBART_CONT
        container image for MegaMolBART training, prepended with registry. e.g.,
        Note that this is a separate (precursor) container from any service associated containers
    PROJECT_PATH
        local path to code. e.g., /home/user/code/NeMo_MegaMolBART
        If code should not be mounted in the container, then the PROJECT_MOUNT_PATH line should
        be removed from the DOCKER_CMD here https://github.com/clara-parabricks/NeMo_MegaMolBART/blob/main/launch.sh#L164
    PROJECT_MOUNT_PATH
        Path to code inside container, e.g. /workspace/nemo
        This can be ignored for non-development runs since code is already inside the container.
        THIS PATH SHOULD BE CHANGED ONLY IF NECESSARY. Many downstream functions depend on it.
    JUPYTER_PORT
        Port for launching jupyter lab, e.g. 8888
    DATA_PATH
        path to data directory. e.g., /scratch/data/ which contains zinc_csv_split
    DATA_MOUNT_PATH
        Path to data inside container. e.g., /data
    REGISTRY
        container registry URL. e.g., nvcr.io. Only required to push/pull containers.
    REGISTRY_USER
        container registry username. e.g., '$oauthtoken' for registry access. Only required to push/pull containers.
    REGISTRY_ACCESS_TOKEN
        container registry access token. e.g., Ckj53jGK... Only required to push/pull containers.
    WANDB_API_KEY
        Weights and Balances API key to upload runs to WandB. Can also be uploaded afterwards., e.g. Dkjdf...
        This value is optional -- Weights and Biases will log data and not upload if missing.
    GITHUB_ACCESS_TOKEN
        GitHub API token to checkout private code repo (required for build only)

EOF
    exit
}

DATA_MOUNT_PATH=${DATA_MOUNT_PATH:=/data}
DATA_PATH=${DATA_PATH:=/tmp}
DOCKERFILE=${DOCKERFILE:=Dockerfile.nemo_checm-v2}
GITHUB_ACCESS_TOKEN=${GITHUB_ACCESS_TOKEN:=""}
GITHUB_BRANCH=${GITHUB_BRANCH:=main}
JUPYTER_PORT=${JUPYTER_PORT:=8888}
MEGAMOLBART_CONT=${MEGAMOLBART_CONT:=nvcr.io/nvidian/clara-lifesciences/megamolbart_training:210830}
NEMO_GITHUB_BRANCH=${NEMO_GITHUB_BRANCH:=main}
NEMO_GITHUB_REPO=${NEMO_GITHUB_REPO:=https://github.com/NVIDIA}
PROJECT_MOUNT_PATH=${PROJECT_MOUNT_PATH:=/workspace}
PROJECT_PATH=${PROJECT_PATH:=$(dirname $(pwd))}
REGISTRY=${REGISTRY:=NotSpecified}
REGISTRY_USER=${REGISTRY_USER:='$oauthtoken'}
RESULT_MOUNT_PATH=${RESULT_MOUNT_PATH:=/result/nemo_experiments}
RESULT_PATH=${RESULT_PATH:=${HOME}/results/nemo_experiments}
WANDB_API_KEY=${WANDB_API_KEY:=$(grep password $HOME/.netrc | cut -d' ' -f4)}


###############################################################################
#
# if $LOCAL_ENV file exists, source it to specify my environment
#
###############################################################################

if [ -e ./$LOCAL_ENV ]
then
    echo sourcing environment from ./$LOCAL_ENV
    . ./$LOCAL_ENV
    write_env=0
else
    echo $LOCAL_ENV does not exist. Writing deafults to $LOCAL_ENV
    write_env=1
fi

###############################################################################
#
# If $LOCAL_ENV was not found, write out a template for user to edit
#
###############################################################################

if [ $write_env -eq 1 ]; then
    echo DATA_MOUNT_PATH=${DATA_MOUNT_PATH} >> $LOCAL_ENV
    echo DATA_PATH=${DATA_PATH} >> $LOCAL_ENV
    echo DOCKERFILE=${DOCKERFILE} >> $LOCAL_ENV
    echo GITHUB_ACCESS_TOKEN=${GITHUB_ACCESS_TOKEN} >> $LOCAL_ENV
    echo GITHUB_BRANCH=${GITHUB_BRANCH} >> $LOCAL_ENV
    echo JUPYTER_PORT=${JUPYTER_PORT} >> $LOCAL_ENV
    echo MEGAMOLBART_CONT=${MEGAMOLBART_CONT} >> $LOCAL_ENV
    echo NEMO_GITHUB_BRANCH=${NEMO_GITHUB_BRANCH} >> $LOCAL_ENV
    echo NEMO_GITHUB_REPO=${NEMO_GITHUB_REPO} >> $LOCAL_ENV
    echo PROJECT_MOUNT_PATH=${PROJECT_MOUNT_PATH} >> $LOCAL_ENV
    echo PROJECT_PATH=${PROJECT_PATH} >> $LOCAL_ENV
    echo REGISTRY=${REGISTRY} >> $LOCAL_ENV
    echo REGISTRY_USER=${REGISTRY_USER} >> $LOCAL_ENV
    echo RESULT_MOUNT_PATH=${RESULT_MOUNT_PATH} >> $LOCAL_ENV
    echo RESULT_PATH=${RESULT_PATH} >> $LOCAL_ENV
    echo WANDB_API_KEY=${WANDB_API_KEY} >> $LOCAL_ENV
fi

###############################################################################
#
#          shouldn't need to make changes beyond this point
#
###############################################################################
# Compare Docker version to find Nvidia Container Toolkit support.
# Please refer https://github.com/NVIDIA/nvidia-docker

DOCKER_VERSION_WITH_GPU_SUPPORT="19.03.0"
if [ -x "$(command -v docker)" ]; then
    DOCKER_VERSION=$(docker version | grep -i version | head -1 | awk '{print $2}')
fi

PARAM_RUNTIME="--runtime=nvidia"
if [ "$DOCKER_VERSION_WITH_GPU_SUPPORT" == "$(echo -e "$DOCKER_VERSION\n$DOCKER_VERSION_WITH_GPU_SUPPORT" | sort -V | head -1)" ];
then
    PARAM_RUNTIME="--gpus all"
fi

#DATE=$(date +%y%m%d)
GITHUB_SHA=$(git ls-remote origin refs/heads/${GITHUB_BRANCH} | head -c7)

# -v ${PROJECT_PATH}:${PROJECT_MOUNT_PATH} \
DOCKER_CMD="docker run \
    --rm \
    --network host \
    ${PARAM_RUNTIME} \
    -p ${JUPYTER_PORT}:8888 \
    -v ${DATA_PATH}:${DATA_MOUNT_PATH} \
    --shm-size=1g \
    --ulimit memlock=-1 \
    --ulimit stack=67108864 \
    -e HOME=${PROJECT_MOUNT_PATH} \
    -w ${PROJECT_MOUNT_PATH}"

build() {
    set -e
    MEGAMOLBART_CONT_BASENAME="$( cut -d ':' -f 1 <<< "$MEGAMOLBART_CONT" )" # Remove tag
    echo "Building MegaMolBART training container..."
    docker build --network host \
        -t ${MEGAMOLBART_CONT_BASENAME}:latest \
        -t ${MEGAMOLBART_CONT_BASENAME}:${GITHUB_SHA} \
        --build-arg GITHUB_ACCESS_TOKEN=${GITHUB_ACCESS_TOKEN} \
        --build-arg GITHUB_BRANCH=${GITHUB_BRANCH} \
        --build-arg NEMO_GITHUB_BRANCH=${NEMO_GITHUB_BRANCH} \
        --build-arg NEMO_GITHUB_REPO=${NEMO_GITHUB_REPO} \
        --build-arg PROJECT_PATH=${PROJECT_MOUNT_PATH} \
        -f ${DOCKERFILE} \
        .

    set +e
    exit
}


push() {
    docker login ${REGISTRY} -u ${REGISTRY_USER} -p ${REGISTRY_ACCESS_TOKEN}
    docker push ${MEGAMOLBART_CONT}:latest
    docker push ${MEGAMOLBART_CONT}:${GITHUB_SHA}
    exit
}


pull() {
    docker login ${REGISTRY} -u ${REGISTRY_USER} -p ${REGISTRY_ACCESS_TOKEN}
    docker pull ${MEGAMOLBART_CONT}
    exit
}


dev() {
    set -x
    DOCKER_CMD="${DOCKER_CMD} -v ${RESULT_PATH}:${RESULT_MOUNT_PATH} --env WANDB_API_KEY=$WANDB_API_KEY --name nemo_dev " 
    ${DOCKER_CMD} -it ${MEGAMOLBART_CONT} bash
    exit
}

attach() {
    set -x
    DOCKER_CMD="docker exec"
    CONTAINER_ID=$(docker ps | grep megamolbart_training:latest | cut -d' ' -f1)
    ${DOCKER_CMD} -it ${CONTAINER_ID}  /bin/bash
    exit
}


root() {
    ${DOCKER_CMD} -it --user root ${MEGAMOLBART_CONT} bash
    exit
}


jupyter() {
    ${DOCKER_CMD} -it ${MEGAMOLBART_CONT} jupyter-lab --no-browser \
        --port=8888 \
        --ip=0.0.0.0 \
        --notebook-dir=/workspace \
        --NotebookApp.password=\"\" \
        --NotebookApp.token=\"\" \
        --NotebookApp.password_required=False
    exit
}


case $1 in
    build)
        ;&
    push)
        ;&
    pull)
        ;&
    dev)
        $@
        ;;
    attach)
        $@
        ;;
    root)
        ;&
    jupyter)
        $1
        ;;
    *)
        usage
        ;;
esac