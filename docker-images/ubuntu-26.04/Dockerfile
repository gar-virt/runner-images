ARG BASE_IMAGE=ubuntu:26.04
FROM ${BASE_IMAGE}
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        7zip \
        build-essential \
        clang-22 \
        clang-format-22 \
        clang-tidy-22 \
        cmake \
        curl \
        g++-15 \
        gcc-15 \
        git \
        ninja-build \
        wget \
        xz-utils \
        zip \
    && rm -rf /var/lib/apt/lists/*
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-15 15 --slave /usr/bin/g++ g++ /usr/bin/g++-15 --slave /usr/bin/gcov gcov /usr/bin/gcov-15
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-22 22 --slave /usr/bin/clang++ clang++ /usr/bin/clang++-22 --slave /usr/bin/clang-format clang-format /usr/bin/clang-format-22 --slave /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-22
RUN curl -sSLo node.tar.xz https://nodejs.org/dist/v24.18.0/node-v24.18.0-linux-x64.tar.xz \
    && echo '55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742 *node.tar.xz' | shasum -c \
    && tar --extract --file node.tar.xz --strip-components 1 --directory /usr/local \
        --exclude 'CHANGELOG.md' --exclude 'LICENSE' --exclude 'README.md' \
    && rm node.tar.xz
RUN node -v \
    && npm -v
ARG BASE_IMAGE
LABEL org.opencontainers.image.source=https://github.com/gar-virt/runner-images
LABEL org.opencontainers.image.description="Runner image based on ${BASE_IMAGE}"
LABEL org.opencontainers.image.licenses=Apache-2.0
