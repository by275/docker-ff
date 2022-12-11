ARG UBUNTU_VER=22.04

FROM ghcr.io/by275/libtorrent:latest-ubuntu${UBUNTU_VER} AS libtorrent
FROM ghcr.io/by275/base:ubuntu AS prebuilt
FROM ghcr.io/by275/base:ubuntu${UBUNTU_VER} AS base

ARG DEBIAN_FRONTEND="noninteractive"
ARG APT_MIRROR="archive.ubuntu.com"

ENV \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

RUN \
    echo "**** prepare apt-get ****" && \
    sed -i "s/archive.ubuntu.com/$APT_MIRROR/g" /etc/apt/sources.list && \
    apt-get update -qq && \
    echo "**** install apt packages ****" && \
    apt-get install -yqq --no-install-recommends \
        `# python3` \
        python3 \
        python3-pip \
        python3-wheel \
        `# pre-compiled python packages` \
        python3-psutil \
        `# core` \
        git \
        sqlite3 \
        unzip \
        wget \
        `# minimal` \
        ffmpeg \
        fuse \
        redis \
        `# util` \
        jq \
        socat \
        vnstat \
        `# torrent_info` \
        'libboost-python[0-9.]+$' \
        && \
    if [ ! -e /usr/bin/python ]; then ln -sf /usr/bin/python3 /usr/bin/python; fi && \
    python -m pip install --upgrade pip && \
    sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf && \
    echo "**** cleanup ****" && \
    rm -rf \
        /root/.cache \
        /tmp/* \
        /var/tmp/* \
        /var/cache/* \
        /var/lib/apt/lists/*

# 
# BUILD
# 
FROM base AS pip

ARG DEBIAN_FRONTEND="noninteractive"

COPY requirements.txt /tmp/

RUN echo "**** install pip packages ****" && \
    python3 -m pip install --root=/bar -r /tmp/requirements.txt --no-warn-script-location


FROM base AS rclone

RUN \
    echo "**** install rclone mod ****" && \
    curl -fsSL https://raw.githubusercontent.com/wiserain/rclone/mod/install.sh | bash


FROM base AS docker-cli

ARG DEBIAN_FRONTEND="noninteractive"

RUN \
    apt-get update -qq && \
    echo "**** install docker-cli ****" && \
    apt-get install -yqq --no-install-recommends \
        gnupg \
        lsb-release && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update -qq && \
    apt-get install -yqq --no-install-recommends --download-only \
        docker-ce-cli && \
    dpkg -x /var/cache/apt/archives/docker-ce-cli*.deb /docker-cli

# 
# COLLECT
# 
FROM base AS collector

# add s6 overlay
COPY --from=prebuilt /s6/ /bar/
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/install-pkg /bar/etc/cont-init.d/30-install-pkg
ADD https://raw.githubusercontent.com/by275/docker-base/main/_/etc/cont-init.d/wait-for-mnt /bar/etc/cont-init.d/40-wait-for-mnt

# add libtorrent libs
COPY --from=libtorrent /libtorrent-build/usr/lib/ /bar/usr/lib/

# add rclone mod
COPY --from=rclone /usr/bin/rclone /bar/usr/bin/

# add docker-cli
COPY --from=docker-cli /docker-cli/ /bar/

# add pip packages
COPY --from=pip /bar/ /bar/

# add local files
COPY root/ /bar/

RUN \
    echo "**** directories ****" && \
    mkdir -p \
        /bar/app \
        && \
    echo "**** install flaskfarm ****" && \
    git -C /bar/app clone --depth 1 -b main \
        "https://github.com/flaskfarm/flaskfarm.git" \
        && \
    echo "**** permissions ****" && \
    chmod a+x \
        /bar/usr/local/bin/* \
        /bar/etc/cont-init.d/* \
        /bar/etc/s6-overlay/s6-rc.d/*/run \
        /bar/etc/s6-overlay/s6-rc.d/*/data/*

RUN \
    echo "**** s6: resolve dependencies ****" && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do mkdir -p "$dir/dependencies.d"; done && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "$dir/dependencies.d/legacy-cont-init"; done && \
    echo "**** s6: create a new bundled service ****" && \
    mkdir -p /tmp/app/contents.d && \
    for dir in /bar/etc/s6-overlay/s6-rc.d/*; do touch "/tmp/app/contents.d/$(basename "$dir")"; done && \
    echo "bundle" > /tmp/app/type && \
    mv /tmp/app /bar/etc/s6-overlay/s6-rc.d/app && \
    echo "**** s6: deploy services ****" && \
    rm /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/legacy-services && \
    touch /bar/package/admin/s6-overlay/etc/s6-rc/sources/top/contents.d/app

# 
# RELEASE
# 
FROM base
LABEL maintainer="by275"
LABEL org.opencontainers.image.source https://github.com/by275/docker-ff

ARG DEBIAN_FRONTEND="noninteractive"

# SYSTEM ENVs
ENV S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    PUID=0 \
    PGID=0 \
    TZ=Asia/Seoul \
    HOME=/data \
    PATH="/data/.local/bin:$PATH" \
    PYTHONPATH="${PYTHONPATH:+$PYTHONPATH:}/app"

# Celery ENVs
ENV \
    CELERY_APP=flaskfarm.main.celery \
    REDIS_PORT=46379

# Flaskfarm ENVs
ENV \
    FF_GIT="https://github.com/flaskfarm/flaskfarm.git" \
    FF_VERSION=main \
    FF_VERSION_DEFAULT=main \
    FF_REPEAT=0 \
    FF_CONFIG="/data/config.yaml" \
    PLUGIN_UPDATE_FROM_PYTHON=false \
    RUNNING_TYPE=docker

# add build artifacts
COPY --from=collector /bar/ /

HEALTHCHECK --interval=30s --timeout=30s --start-period=50s --retries=3 \
    CMD /usr/local/bin/healthcheck

VOLUME /data
WORKDIR /data

ENTRYPOINT ["/init"]
