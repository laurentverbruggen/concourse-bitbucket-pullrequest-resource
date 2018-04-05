FROM gliderlabs/alpine:edge

RUN apk --no-cache add \
  bash=4.4.19-r1 \
  ca-certificates=20171114-r0 \
  curl=7.59.0-r0 \
  git=2.16.3-r0 \
  jq=1.5-r5 \
  openssh-client=7.6_p1-r1

# can't `git pull` unless we set these
RUN git config --global user.email "git@localhost" && \
    git config --global user.name "git"

COPY scripts/install_git_lfs.sh install_git_lfs.sh
RUN ./install_git_lfs.sh

COPY assets /opt/resource
