# Build environment mirroring .github/workflows/build-bpi-r4-deploy.yml
# (ubuntu-22.04 runner + its "Install build dependencies" step).
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    LC_ALL=C.UTF-8 \
    LANG=C.UTF-8

# First line-block: the exact package list from the workflow.
# Second line-block: things the hosted GitHub runner ships out of the box
# that OpenWrt's build system also needs (certs for https clones, xz/zstd
# for source archives and the SDK tarball, curl, bzip2).
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
      gettext libncurses-dev libssl-dev python3-distutils python3-setuptools \
      rsync swig unzip zlib1g-dev file wget libelf-dev ccache git \
      ca-certificates curl bzip2 xz-utils zstd time procps \
    && rm -rf /var/lib/apt/lists/*

# OpenWrt refuses to build as root; run as an unprivileged user whose
# UID/GID match the host user so the bind-mounted work tree stays yours.
ARG UID=1000
ARG GID=1000
RUN (getent group ${GID} || groupadd -g ${GID} builder) \
 && useradd -m -u ${UID} -g ${GID} -s /bin/bash builder

USER builder
WORKDIR /work
