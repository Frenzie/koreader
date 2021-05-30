#!/usr/bin/env bash

CI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${CI_DIR}/common.sh"

# print some useful info
echo "BUILD_DIR: ${CI_BUILD_DIR}"
echo "pwd: $(pwd)"
ls

# toss submodules if there are any changes
# if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
# "--ignore-submodules=dirty", removed temporarily, as it did not notice as
# expected that base was updated and kept using old cached base
if [ "$(git status --ignore-submodules=dirty --porcelain)" ]; then
    # what changed?
    git status
    # purge and reinit submodules
    git submodule deinit -f .
    git submodule update --init
else
    echo -e "${ANSI_GREEN}Using cached submodules."
fi

#install our own updated shellcheck
SHELLCHECK_VERSION="v0.7.2"
SHELLCHECK_URL="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION?}/shellcheck-${SHELLCHECK_VERSION?}.linux.x86_64.tar.xz"
if ! command -v shellcheck; then
    curl -sSL "${SHELLCHECK_URL}" | tar --exclude 'SHA256SUMS' --strip-components=1 -C "${HOME}/bin" -xJf -
    chmod +x "${HOME}/bin/shellcheck"
    shellcheck --version
else
    echo -e "${ANSI_GREEN}Using cached shellcheck."
fi

# install shfmt
SHFMT_VERSION="v3.3.0"
SHFMT_URL="https://github.com/mvdan/sh/releases/download/${SHFMT_VERSION}/shfmt_${SHFMT_VERSION}_linux_amd64"
if [ "$(shfmt --version)" != ${SHFMT_VERSION} ]; then
    curl -sSL "${SHFMT_URL}" -o "${HOME}/bin/shfmt"
    chmod +x "${HOME}/bin/shfmt"
else
    echo -e "${ANSI_GREEN}Using cached shfmt."
fi
