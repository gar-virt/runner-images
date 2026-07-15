#!/bin/bash

set -e

check_gpg_fingerprints() {
    local file=$1
    shift
    local known_fingerprints=("${@}")
    local present_fingerprints
    readarray -t present_fingerprints < <(gpg --show-keys --with-colons "${file}" | grep 'fpr:')
    local known_count=${#known_fingerprints[@]}
    local present_count=${#present_fingerprints[@]}
    if [[ "${known_count}" == 0 || "${present_count}" == 0 ]]; then
        echo "Bad fingerprint count"
        return 1
    fi
    local valid_present_count=0
    local pfp kfp
    for pfp in "${present_fingerprints[@]}"; do
        for kfp in "${known_fingerprints[@]}"; do
            kfp=fpr:::::::::${kfp}:
            if [[ "${pfp}" == "${kfp}" ]]; then
                valid_present_count=$((valid_present_count + 1))
            fi
        done
    done
    local valid_known_count=0
    for kfp in "${known_fingerprints[@]}"; do
        kfp=fpr:::::::::${kfp}:
        for pfp in "${present_fingerprints[@]}"; do
            if [[ "${pfp}" == "${kfp}" ]]; then
                valid_known_count=$((valid_known_count + 1))
            fi
        done
    done
    if [[ "${valid_present_count}" != "${present_count}" || "${valid_known_count}" != "${known_count}" ]]; then
        echo "Found unknown GPG fingerprint"
        return 1
    fi
}

install_docker() {
    known_fingerprints=(
        9DC858229FC7DD38854AE2D88D81803C0EBFCD88
        D3306A018370199E527AE7997EA0A9C3F273FCD8
    )
    apt-get install -y ca-certificates curl
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /tmp/docker.asc
    check_gpg_fingerprints /tmp/docker.asc "${known_fingerprints[@]}"
    install -m 0755 -d /etc/apt/keyrings
    cp --force /tmp/docker.asc /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_images() {
    images=(
        "${DOCKER_TAG}:ubuntu-26.04"
        "${DOCKER_TAG}:ubuntu-24.04"
    )
    for image in "${images[@]}"; do
        docker pull "${image}"
    done
}

install_gitea_runner() {
    version=1.0.8-sl.1
    filename=gitea-runner-v${version}-linux-amd64
    sha256_hash=eae4ff11e3a0378067b251eac036b76a437b9788950fec849108ace2aa99112a
    if [[ -f "${SEED_DIR}/${filename}" ]]; then
        archive_path=${SEED_DIR}/${filename}
    else
        temp_path=/tmp/gitea-runner.xz
        curl -sSLfo "${temp_path}" "https://github.com/gar-virt/gitea-runner/releases/download/v${version}/gitea-runner-v${version}-linux-amd64.xz"
        archive_path=${temp_path}
    fi
    echo "${sha256_hash} ${archive_path}" | sha256sum -c
    (cd /tmp && xz --decompress --keep "${archive_path}")
    cp --force /tmp/gitea-runner /usr/local/bin/gitea-runner
    chmod 0755 /usr/local/bin/gitea-runner
    if [[ ! -z "${temp_path+x}" ]]; then
        rm --force "${temp_path}"
    fi
}

remove_snapd() {
    apt-get autoremove --purge snapd -y
}

if [[ -z "${SEED_DIR+x}" ]]; then
    echo "Missing SEED_DIR environment variable."
    exit 1
fi

if [[ -z "${DOCKER_TAG+x}" ]]; then
    echo "Missing DOCKER_TAG environment variable."
    exit 1
fi

if [[ ! -d "${SEED_DIR}" ]]; then
    echo "Invalid seed directory: ${SEED_DIR}"
    exit 1
fi

remove_snapd
install_docker
install_docker_images
install_gitea_runner
