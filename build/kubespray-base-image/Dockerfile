FROM cargo.caicloud.xyz/library/ubuntu:18.04

RUN mkdir -p /kubespray/tests
WORKDIR /kubespray
RUN apt update -y && \
    apt install -y \
    libssl-dev python3-dev sshpass apt-transport-https jq moreutils \
    ca-certificates curl gnupg2 software-properties-common python3-pip rsync vim \
    && rm -rf /var/lib/apt/lists/* \
    && curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.19.3/bin/linux/amd64/kubectl \
    && chmod a+x kubectl && mv kubectl /usr/local/bin/kubectl
COPY requirements.txt .
COPY tests/requirements.txt ./tests/
RUN /usr/bin/python3 -m pip install pip -U && /usr/bin/python3 -m pip install -r tests/requirements.txt && \
    python3 -m pip install -r requirements.txt && update-alternatives --install /usr/bin/python python /usr/bin/python3 1

# Some tools like yamllint need this
ENV LANG=C.UTF-8
