#!/bin/bash

set -e -u
set -o pipefail

[ -s ~/.config/udv/pkgbuild.env ] && source ~/.config/udv/pkgbuild.env
SUDO=${WITH_SUDO:+sudo}

usage()
{
    cat >&2 << EOF
Применение:
    ${0##*\/} <BRANCH>

Аргументы:
    BRANCH: Название ветки. Должно соответствовать выражению:
        ^(master|v[0-9]+[.][0-9]+)$

EOF
    exit 1
}

[ $# -eq 1 ] || usage

BRANCH="$1"
[[ "$BRANCH" =~ ^(master|v[0-9]+[.][0-9]+)$ ]] || usage

exec $SUDO podman build \
    --rm --force-rm --no-cache \
    --build-arg=branch=$BRANCH \
    --tag dtpk-pkgbuild:$BRANCH .
