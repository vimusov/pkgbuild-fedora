FROM scratch
ADD layer.tar /

RUN rm -rf /etc/yum.repos.d/*
COPY base.repo /etc/yum.repos.d/

# https://bugzilla.redhat.com/show_bug.cgi?id=2066851
RUN \
    dnf -y clean all \
    && dnf -y update \
    && dnf -y upgrade \
    && dnf -y install \
        'dnf-command(builddep)' \
        'dnf-command(download)' \
        createrepo_c \
        curl \
        iproute \
        python3-devel \
        python3-rpm-macros \
        rpmdevtools \
        zip \
        zstd \
    && sed -E \
        -i 's/^(.*)goal\.run\(\)$/\1goal.run(ignore_weak_deps=True)/' \
        /usr/lib/python3.*/site-packages/dnf-plugins/download.py \
    && grep -qFm1 ignore_weak_deps \
        /usr/lib/python3.*/site-packages/dnf-plugins/download.py

COPY ./entry.sh /entry.sh
