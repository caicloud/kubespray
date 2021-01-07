FROM cargo.caicloud.xyz/library/debian:stretch

RUN sed -i 's/deb.debian.org/mirrors.ustc.edu.cn/g' /etc/apt/sources.list && \
    apt-get update && \
    apt-get install -y keepalived ipset curl ipset && \
    rm -rf /var/lib/apt/lists/*

