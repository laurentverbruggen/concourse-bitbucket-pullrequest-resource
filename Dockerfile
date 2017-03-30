FROM alpine

ADD assets/ /opt/resource/
ADD scripts/install_git_lfs.sh install_git_lfs.sh

RUN set -ex && \
    apk --no-cache add bash ca-certificates curl git jq && \
    git config --global user.email "git@localhost" && \
    git config --global user.name "git" && \
    ./install_git_lfs.sh && \
    chmod +x /opt/resource/*
