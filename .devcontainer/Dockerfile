# canonscope development container.
#
# WHY DEBIAN TRIXIE, specifically: it is the base of Raspberry Pi OS (trixie),
# the reference controller OS, and what the release .debs are built on. If a
# package resolves here it resolves there; if chdkptp builds here it builds
# there.
#
# WHAT THIS CONTAINER CANNOT DO: drive the camera. USB passthrough would need
# device paths that change on every replug, and udev rules execute on the HOST
# -- so the gvfsd-gphoto2 problem and its fix both live outside this image.
# Camera work happens on the host. See .devcontainer/README.md.
FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# Grouped by what needs them, so it is obvious what a removal would break.
RUN apt-get update && apt-get install -y --no-install-recommends \
    `# shell and the basics every tool in tools/ assumes` \
      bash coreutils findutils sed gawk grep diffutils procps \
      ca-certificates curl jq git unzip xz-utils less \
    `# building chdkptp: Lua 5.2 specifically, and the libusb 0.1 API` \
      build-essential pkg-config \
      liblua5.2-dev lua5.2 libusb-dev libreadline-dev \
    `# make-card.sh -- present so the script can be exercised against a` \
    `# loopback image; writing a real card still happens on the host` \
      util-linux parted dosfstools fdisk \
    `# canonscope preview --format png` \
      imagemagick \
    `# the MCP server and the test suites` \
      python3 python3-venv \
    `# lint` \
      shellcheck \
    `# quality of life for a container people actually work in` \
      sudo tmux nano \
 && rm -rf /var/lib/apt/lists/*

# uv, pinned. The project already uses it for the MCP venv, and it creates
# virtualenvs without needing ensurepip -- which is exactly what bit this
# project on the host (python3-venv was missing, `python3 -m venv` failed).
ARG UV_VERSION=0.13.7
RUN curl -fsSL "https://astral.sh/uv/${UV_VERSION}/install.sh" \
      | env UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 sh \
 && uv --version

# A normal user with passwordless sudo. make-card.sh is built around running
# unprivileged -- every check happens as you, and it escalates only after the
# target is confirmed -- so running as root would defeat its design.
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=1000
RUN groupadd --gid "$USER_GID" "$USERNAME" \
 && useradd --uid "$USER_UID" --gid "$USER_GID" -m -s /bin/bash "$USERNAME" \
 && echo "$USERNAME ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/"$USERNAME" \
 && chmod 0440 /etc/sudoers.d/"$USERNAME"

USER $USERNAME
WORKDIR /workspaces/canonscope

# CANONSCOPE_IN_CONTAINER is reported by .devcontainer/verify.sh, and is there
# for any script that needs to refuse something requiring real hardware.
ENV CANONSCOPE_IN_CONTAINER=1
