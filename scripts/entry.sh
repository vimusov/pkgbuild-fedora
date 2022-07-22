#!/bin/bash

set -u
set -o pipefail

EMER_SHELL=0
readonly COMMIT=HEAD
readonly RESULT_DIR=/result
readonly SRC_DIR_PATH=/sources
readonly LOCAL_REPO_PATH=/local_repo

show_err()
{
    echo -e "\e[1;31m!! $@ \e[m"
}

on_error()
{
    show_err "Unexpected error occurred. Dropping to an emergency shell.\n"
    /bin/bash
    builtin exit 1
}

show_msg()
{
    echo -e "\e[0;32m>> $@ \e[m"
}

build_srpm()
{
    local packer=''
    local pkgver=''
    local pkgname=''
    local new_spec=''
    local org_spec=''
    local src_name=''
    local file_path=''
    local many_specs=0
    local sub_dir_name=''
    local tmp_spec=/tmp/half.spec
    local tmp_src_dir=/tmp/prep-spec

    for file_path in "$SRC_DIR_PATH"/*.spec; do
        [ -s "$file_path" ] || continue
        [ -z "$org_spec" ] && org_spec="$file_path" || many_specs=1
    done

    if ! [ -s "$org_spec" ]; then
        show_err "No SPEC file found in '$SRC_DIR_PATH'."
        return 1
    fi

    if [ $many_specs -ne 0 ]; then
        show_err "More than one SPEC file found in '$SRC_DIR_PATH' so I've no idea what to do."
        return 1
    fi

    pkgname=$(rpm -q --qf '%{name}\n' --specfile "$org_spec" | head -n1)
    if [ -z "$pkgname" ]; then
        show_err "Package name not found in '$org_spec'."
        return 1
    fi

    pkgver=$(rpm -q --qf '%{version}\n' --specfile "$org_spec" | head -n1)
    if [ -z "$pkgver" ]; then
        show_err "Package version not found in '$org_spec'."
        return 1
    fi

    if [ $(basename "$org_spec") != "${pkgname}.spec" ]; then
        show_err "Name of SPEC file '$org_spec'. does not match with package name '$pkgname'."
        return 1
    fi

    if type rpmspec > /dev/null; then
        src_name=`rpmspec -P "$org_spec" | sed -n -r  's|^Source0?:\s+(.*/)?(.*)$|\2|p'`
    else
        show_err "Unable to get 'Source0' file name from '$org_spec'."
        return 1
    fi

    mkdir "$tmp_src_dir"
    find "$SRC_DIR_PATH" -maxdepth 1 -not -type d -not -name "*.spec" -exec cp -v '{}' "$tmp_src_dir" \;
    new_spec="$tmp_src_dir"/${pkgname}.spec

    # Source0 отсутствует в SPEC.
    if [ -z "$src_name" ]; then
        show_msg "Source0 is not defined, creating archive from RAW sources."

        # TODO: Заменить gzip на zstd когда появится его поддержка в RPM.
        tar --create \
            --exclude-vcs --exclude='*.spec' \
            --transform="s|^[.]|${pkgname}-$pkgver|" \
            --directory="$SRC_DIR_PATH" . \
            | gzip -1 > "$tmp_src_dir"/"${pkgname}-${pkgver}.tgz"
        [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" != "00" ] && return 1

        {
            echo "Source0: %{name}-%{version}.tgz"
            cat "$org_spec"
        } >| "$tmp_spec"

        if grep -qEm1 '^%prep' "$tmp_spec"; then
            awk '{ print; }  /^%prep/ { print "%setup -q"; }' < "$tmp_spec" >| "$new_spec"
        else
            sed -r '/^%build/i %prep\n%setup -q\n'            < "$tmp_spec" >| "$new_spec"
        fi
        [ $? -eq 0 ] || return 1

    # Файл с архивом, указанным в Source0, в каталоге есть.
    elif [ -s "$SRC_DIR_PATH"/"$src_name" ]; then
        show_msg "Source0 is defined and all files are ready to use."
        cp -v "$org_spec" "$new_spec"

    # В Source0 указано название архива, но самого архива нет.
    elif [ -n "$src_name" ]; then
        case "$src_name" in
            *.tar)
                packer='cat'
                sub_dir_name="${src_name%.tar}"
                ;;
            *.tgz|*.tar.gz)
                packer='gzip -1'
                sub_dir_name="${src_name%.tgz}"
                sub_dir_name="${src_name%.tar.gz}"
                ;;
            *.tbz2|*.tar.bz2)
                packer='bzip2 -1'
                sub_dir_name="${src_name%.tbz2}"
                sub_dir_name="${src_name%.tar.bz2}"
                ;;
            *.txz|*.tar.xz)
                packer='xz -1'
                sub_dir_name="${src_name%.txz}"
                sub_dir_name="${src_name%.tar.xz}"
                ;;
            *.tar.zst|*.tar.zstd)
                packer='zstd -1'
                sub_dir_name="${src_name%.tar.zstd}"
                sub_dir_name="${src_name%.tar.zst}"
                ;;
            *.zip)
                packer='zip -0'
                sub_dir_name="${src_name%.zip}"
                ;;
            *)
                show_err "Invalid archive name '$src_name' in Source0 in SPEC."
                return 1
                ;;
        esac
        if ! [ -d "$SRC_DIR_PATH"/"$sub_dir_name" ]; then
            show_err "Source0 in SPEC set to '$src_name' but directory '$sub_dir_name' is not found."
            return 1
        fi
        show_msg "Source0 is defined but archive not found, building '$src_name' from directory '$sub_dir_name'."
        tar --create \
            --exclude-vcs --exclude='*.spec' \
            --directory="$SRC_DIR_PATH" "$sub_dir_name" \
            | $packer > "$tmp_src_dir"/"$src_name"
        [ "${PIPESTATUS[0]}${PIPESTATUS[1]}" != "00" ] && return 1
        cp -v "$org_spec" "$new_spec"

    # Что-то странное...
    else
        show_err "Unsupported layout of sources files."
        return 1
    fi

    show_msg "Building SRPM..."
    rpmbuild \
        --define "_specdir ${tmp_src_dir}/spec" \
        --define "_sourcedir $tmp_src_dir" \
        --define "_builddir ${tmp_src_dir}/build" \
        --define "_buildrootdir ${tmp_src_dir}/buildroot" \
        --define "_rpmdir ${tmp_src_dir}/rpm" \
        --define "_srcrpmdir $RESULT_DIR" \
        --target=x86_64 -bs "$new_spec"
}

set_local_repo()
{
    local pkg_name=''
    local pkg_path=''
    local excludes=''
    local tmp_excludes=()
    local pkg_list=/tmp/local-repo-rpms.list

    find "$LOCAL_REPO_PATH" -type f \( -name '*.rpm' -a -not -name '*.src.rpm' \) > "$pkg_list"
    while read pkg_path; do
        [ -s $pkg_path ] || continue
        pkg_name=$(rpm -q --nosignature --nodigest --queryformat '%{name}' -p $pkg_path)
        [ -n $pkg_name ] || continue
        tmp_excludes+=($pkg_name)
    done < "$pkg_list"

    excludes=${tmp_excludes[*]}
    excludes=${excludes// /,}
    if [ -z "$excludes" ]; then
        show_msg "Local repository '$LOCAL_REPO_PATH' is empty."
        return 0
    fi

    echo "Excluding local RPMs from all repos: ${excludes}."
    echo "$excludes" > /etc/dnf/vars/local_excludes

    [ -d "$LOCAL_REPO_PATH"/repodata ] && rm -rfv "$LOCAL_REPO_PATH"/repodata
    chmod 0777 "$LOCAL_REPO_PATH"
    createrepo_c "$LOCAL_REPO_PATH"

    cat > /etc/yum.repos.d/local.repo <<EOF
[local]
name=local
baseurl=file://$LOCAL_REPO_PATH
enabled=1
gpgcheck=0
EOF
}

main()
{
    local file_path=''
    local many_srpms=0
    local srpm_file_path=''
    local tmp_src_dir=/tmp/pkgs-root

    show_msg "Going to build RPM, looking for sources..."

    chmod 0777 "$RESULT_DIR"
    build_srpm || return 1

    show_msg "Looking for SRPMs..."

    for file_path in "$RESULT_DIR"/*.src.rpm; do
        [ -s "$file_path" ] || continue
        [ -z "$srpm_file_path" ] && srpm_file_path="$file_path" || many_srpms=1
    done
    if ! [ -s "$srpm_file_path" ]; then
        show_err "No SRPM found in '$RESULT_DIR'."
        return 1
    fi
    if [ $many_srpms -ne 0 ]; then
        show_err "More than one SRPM found in '$RESULT_DIR'. so I've no idea what to do."
        return 1
    fi

    if [ -d "$LOCAL_REPO_PATH" ]; then
        show_msg "Setting up local repository."
        set_local_repo || return 1
    else
        show_msg "Local repository is not used."
    fi

    show_msg "Found SRPM '$srpm_file_path'. Installing build dependencies."
    dnf makecache || return 1
    dnf -y update || return 1
    dnf -y builddep --srpm "$srpm_file_path" || return 1

    show_msg "Building RPM..."
    mkdir "$tmp_src_dir"
    rpmbuild \
        --define "_specdir ${tmp_src_dir}/spec" \
        --define "_sourcedir ${tmp_src_dir}/sources" \
        --define "_builddir ${tmp_src_dir}/build" \
        --define "_buildrootdir ${tmp_src_dir}/buildroot" \
        --define "_rpmdir ${tmp_src_dir}/rpms" \
        --define "_srcrpmdir ${tmp_src_dir}/srpms" \
        -rb "$srpm_file_path" || return 1

    show_msg "Moving RPMs to the target directory."
    find "$tmp_src_dir"/rpms -type f -name '*.rpm' -exec mv -vf '{}' "$RESULT_DIR" \;

    show_msg "Build completed successfully."
}

while getopts "hdel:" opt; do
    case $opt in
        d)
            set -x
            ;;
        e)
            trap on_error ERR
            ;;
        \?)
            echo "ERROR: Invalid argument '$OPTARG'." >&2
            exit 1
            ;;
    esac
done

main
