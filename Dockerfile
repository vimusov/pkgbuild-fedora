ARG branch=no-such-branch
FROM dtpk-base-image:$branch

RUN dnf \
    -y \
    install   \
    createrepo_c \
    curl         \
    'dnf-command(builddep)' \
    'dnf-command(download)' \
    python3-devel \
    python3-rpm-macros \
    rpmdevtools        \
    zip \
    zstd

# https://bugzilla.redhat.com/show_bug.cgi?id=2066851
RUN sed -E \
    -i 's/^(.*)goal\.run\(\)$/\1goal.run(ignore_weak_deps=True)/' \
    /usr/lib/python3.*/site-packages/dnf-plugins/download.py
RUN grep -qFm1 ignore_weak_deps \
    /usr/lib/python3.*/site-packages/dnf-plugins/download.py

COPY ./scripts/* /build/scripts/

ENTRYPOINT ["/build/scripts/entry.sh"]
