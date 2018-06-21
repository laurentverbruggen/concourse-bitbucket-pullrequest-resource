#!/bin/sh

set -eux

_main() {
  local tmpdir
  tmpdir="$(mktemp -d git_lfs_install.XXXXXX)"

  cd "$tmpdir"
  version=2.4.2
  /usr/bin/curl -Lo git.tar.gz https://github.com/git-lfs/git-lfs/releases/download/v${version}/git-lfs-linux-amd64-${version}.tar.gz
  gzip -dc git.tar.gz |  tar -xvf -
  mv git-lfs-${version}/git-lfs /usr/bin
  cd ..
  rm -rf "$tmpdir"
  git lfs install --skip-smudge
}

_main "$@"
