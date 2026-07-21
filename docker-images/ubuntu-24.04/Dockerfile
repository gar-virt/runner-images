FROM ubuntu:24.04
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y \
        7zip \
        build-essential \
        clang-20 \
        clang-format-20 \
        clang-tidy-20 \
        cmake \
        curl \
        g++-14 \
        gcc-14 \
        git \
        ninja-build \
        wget \
        zip \
    && rm -rf /var/lib/apt/lists/*
RUN update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 14 --slave /usr/bin/g++ g++ /usr/bin/g++-14 --slave /usr/bin/gcov gcov /usr/bin/gcov-14
RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-20 20 --slave /usr/bin/clang++ clang++ /usr/bin/clang++-20 --slave /usr/bin/clang-format clang-format /usr/bin/clang-format-20 --slave /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-20
RUN curl -sSLo node.tar.xz https://nodejs.org/dist/v24.18.0/node-v24.18.0-linux-x64.tar.xz \
    && echo '55aa7153f9d88f28d765fcdad5ae6945b5c0f98a36881703817e4c450fa76742 *node.tar.xz' | shasum -c \
    && tar --extract --file node.tar.xz --strip-components 1 --directory /usr/local \
        --exclude 'CHANGELOG.md' --exclude 'LICENSE' --exclude 'README.md' \
    && rm node.tar.xz
RUN node -v \
    && npm -v
