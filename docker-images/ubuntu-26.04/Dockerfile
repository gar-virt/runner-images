FROM ubuntu:26.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        7zip \
        build-essential \
        cmake \
        curl \
        g++ \
        gcc \
        git \
        ninja-build \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*
RUN curl -sSLo node.tar.xz https://nodejs.org/dist/v24.18.0/node-v24.18.0-linux-x64.tar.xz \
    && echo '55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742 *node.tar.xz' | shasum -c \
    && tar --extract --file node.tar.xz --strip-components 1 --directory /usr/local \
        --exclude 'CHANGELOG.md' --exclude 'LICENSE' --exclude 'README.md' \
    && rm node.tar.xz
RUN node -v \
    && npm -v
