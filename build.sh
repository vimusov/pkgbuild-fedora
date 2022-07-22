#!/bin/bash

set -e -u
set -o pipefail

[ -s ~/.config/udv/pkgbuild.env ] && source ~/.config/udv/pkgbuild.env
SUDO=${WITH_SUDO:+sudo}

DEBUG=
BRANCH='master'
EMER_SHELL=
LOCAL_REPO_PATH=''

usage()
{
    cat >&2 << EOF
Применение:
    ${0##*\/} [-h] [-d] [-e] [-l <DIR>] [-b <BRANCH>] <SRC_DIR> <RESULT_DIR>

Ключи:
    -h: Справка;
    -d: Включить отладку (добавить опцию '-x' в скрипт внутри контейнера);
    -e: Запускать bash при ошибках сборки для интерактивной отладки;
    -b <BRANCH>: Название ветки, по-умолчанию: '$BRANCH'.
                 Должна соответствовать выражению: ^(master|v[0-9]+[.][0-9]+)$
    -l <DIR>: Подключить локальный репозиторий из каталога <DIR>;

Аргументы:
    SRC_DIR: Путь к каталогу с исходникам для сборки;
    RESULT_DIR: Путь к каталогу для собранных пакетов;

EOF
    exit 1
}

while getopts "hdeb:l:" opt; do
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
        b)
            BRANCH="$OPTARG"
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

[[ "$BRANCH" =~ ^(master|v[0-9]+[.][0-9]+)$ ]] || usage

SRC_DIR_PATH=$(readlink -e "$1")
RESULT_DIR=$(readlink -m "$2")
mkdir -p "$RESULT_DIR"

exec $SUDO podman run -it --rm \
    --volume "$RESULT_DIR":/result \
    --volume "$SRC_DIR_PATH":/sources:ro \
    ${LOCAL_REPO_PATH:+--volume "$LOCAL_REPO_PATH":/local_repo} \
    dtpk-pkgbuild:$BRANCH \
    ${DEBUG:+-d} \
    ${EMER_SHELL:+-e}
