#!/bin/bash

set -ueo pipefail

DOAS=${WITH_DOAS:-doas}
DEBUG=
EMER_SHELL=
ALLOW_INTERNET=
LOCAL_REPO_PATH=''
readonly TAG='pkgbuild-fedora'
readonly IMG_NAME='Fedora-Container-Base-37-1.7.x86_64.tar.xz'
readonly BASE_IMG_URL="https://mirror.yandex.ru/fedora/linux/releases/37/Container/x86_64/images/$IMG_NAME"

usage()
{
    cat >&2 << EOF
Usage:
    ${0##*\/} [-h] [-d] [-e] [-i] [-l <DIR>] <SRC_DIR> <RESULT_DIR>

Keys:
    -h: Show this help;
    -d: Enable debug (add option '-x');
    -e: Run shell if RPM build failed;
    -i: Enable Internet access for building stage;
    -l <DIR>: Enable local repo from the directory <DIR>;

Args:
    SRC_DIR: Path to directory with sources and SPEC;
    RESULT_DIR: Path to directory with result RPMs;

EOF
    exit 1
}

while getopts "hdiel:" opt; do
    case $opt in
        h)
            usage
            ;;
        d)
            DEBUG=y
            ;;
        e)
            EMER_SHELL=y
            ;;
        i)
            ALLOW_INTERNET=1
            ;;
        l)
            LOCAL_REPO_PATH=$(readlink -e "$OPTARG")
            ;;
        \?)
            usage
            ;;
    esac
done

shift $(($OPTIND-1))
[ $# -eq 2 ] || usage

SRC_DIR_PATH=$(readlink -e "$1")
RESULT_DIR=$(readlink -m "$2")

if [ -d "$RESULT_DIR" ]; then
    echo "ERROR: Result dir '$RESULT_DIR' is exist." >&2
    exit 1
else
    mkdir -p "$RESULT_DIR"
fi

prepare()
{
    $DOAS podman images --all | grep -qF "$TAG" && return 0 || true

    if ! [ -s "$IMG_NAME" ]; then
        local loader=''
        for loader in aria2c wget curl; do
            type $loader > /dev/null 2>&1 && break || continue
        done
        if [ -z "$loader" ]; then
            echo "ERROR: Unable to find loader, install aria2c|wget|curl." >&2
            return 1
        fi
        $loader "$BASE_IMG_URL"
    fi

    [ -s layer.tar ] || tar Jxf "$IMG_NAME" --wildcards '*/layer.tar' --strip-components=1

    $DOAS podman build \
        --rm --force-rm --no-cache \
        --network=host \
        --tag $TAG \
        .
}

prepare

# SYS_ADMIN нужен unshare -net
# NET_ADMIN нужен ip link set up dev lo

exec $DOAS podman run \
    -it --rm \
    --network=host \
    --cap-add=SYS_ADMIN \
    --cap-add=NET_ADMIN \
    --volume "$RESULT_DIR":/result \
    --volume "$SRC_DIR_PATH":/sources:ro \
    ${LOCAL_REPO_PATH:+--volume "$LOCAL_REPO_PATH":/local_repo} \
    $TAG \
    /entry.sh \
    ${DEBUG:+-d} \
    ${EMER_SHELL:+-e} \
    ${ALLOW_INTERNET:+-i}
