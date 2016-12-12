FROM gliderlabs/alpine:edge

RUN apk --update add \
  ca-certificates \
  bash \
  jq \
  curl \
  git

# can't `git pull` unless we set these
RUN git config --global user.email "git@localhost" && \
    git config --global user.name "git"

ADD assets/ /opt/resource/
RUN chmod +x /opt/resource/*
