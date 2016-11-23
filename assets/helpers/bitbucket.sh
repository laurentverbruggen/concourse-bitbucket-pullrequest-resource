#!/bin/bash

set -e

ASSETS=$(cd "$(dirname "$0")" && pwd)
source $ASSETS/helpers/utils.sh

VALUES_LIMIT=100

bitbucket_request() {
  # $1: host
  # $2: path
  # $3: query
  # $4: data
  # $5: url base path
  # $6: netrc file (default: $HOME/.netrc)
  # $7: HTTP method (default: POST for data, GET without data)
  # $8: recursive data for bitbucket paging

  local data="$4"
  local path=${5:-rest/api/1.0}
  local netrc_file=${6:-$HOME/.netrc}
  local method="$7"
  local recursive=${8:-limit=${VALUES_LIMIT}}

  local request_url="${1}/${path}/${2}?${recursive}&${3}"
  local request_result=$(tmp_file_unique bitbucket-request)
  local request_data=$(tmp_file_unique bitbucket-request-data)

  # deletes the temp files
  request_result_cleanup() {
    rm -f "$request_result"
    rm -f "$request_data"
  }

  # register the cleanup function to be called on the EXIT signal
  trap request_result_cleanup EXIT

  local extra_options=""
  if [ -n "$data" ]; then
    method=${method:-POST}
    jq '.' <<< "$data" > "$request_data"
    extra_options="-H \"Content-Type: application/json\" -d @\"$request_data\""
  fi

  if [ -n "$method" ]; then
    extra_options+=" -X $method"
  fi

  curl_cmd="curl -s --netrc-file \"$netrc_file\" $extra_options \"$request_url\" > \"$request_result\""
  if ! eval $curl_cmd; then
    log "Bitbucket request $request_url failed"
    exit 1
  fi

  if ! jq -c '.' < "$request_result" > /dev/null 2> /dev/null; then
    log "Bitbucket request $request_url failed (invalid JSON): $(cat "$request_result")"
    exit 1
  fi

  if [ "$(jq -r '.isLastPage' < "$request_result")" == "false" ]; then
    local nextPage=$(jq -r '.nextPageStart' < "$request_result")
    local nextResult=$(bitbucket_request "$1" "$2" "$3" "$4" "$5" "$6" "$7" "start=${nextPage}&limit=${VALUES_LIMIT}")
    jq -c '.values' < "$request_result" | jq -c ". + $nextResult"
  elif [ "$(jq -c '.values' < "$request_result")" != "null" ]; then
    jq -c '.values' < "$request_result"
  elif [ "$(jq -c '.errors' < "$request_result")" == "null" ]; then
    jq '.' < "$request_result"
  else
    log "Bitbucket request ($request_url) failed: $(cat $request_result)"
    exit 1
  fi

  # cleanup
  request_result_cleanup
}

bitbucket_pullrequest() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: pullrequest id
  # $5: netrc file (default: $HOME/.netrc)
  log "Retrieving pull request #$4 for $2/$3"
  bitbucket_request "$1" "projects/$2/repos/$3/pull-requests/$4" "" "" "" "$5"
}

bitbucket_pullrequest_merge() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: pullrequest id
  # $5: netrc file (default: $HOME/.netrc)
  log "Retrieving pull request merge status #$4 for $2/$3"
  bitbucket_request "$1" "projects/$2/repos/$3/pull-requests/$4/merge" "" "" "" "$5"
}

bitbucket_pullrequest_overview_comments() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: pullrequest id
  # $5: netrc file (default: $HOME/.netrc)
  log "Retrieving pull request comments #$4 for $2/$3"
  set -o pipefail; bitbucket_request "$1" "projects/$2/repos/$3/pull-requests/$4/activities" "" "" "" "$5" | \
    jq 'map(select(.action == "COMMENTED" and .commentAction == "ADDED" and .commentAnchor == null)) |
        sort_by(.createdDate) | reverse |
        map({ id: .comment.id, version: .comment.version, text: .comment.text, createdDate: .comment.createdDate })'
}

bitbucket_pullrequest_progress_commit_match() {
  # $1: pull request comment
  # $2: pull request hash
  # $3: type of build to match (default: Started|Finished)
  local comment="$1"
  local hash="$2"
  local type=${3:-(Started|Finished)}
  echo "$comment" | grep -Ec "^\[\*Build$type\* \*\*${BUILD_PIPELINE_NAME}\-${BUILD_JOB_NAME}\*\* for $hash" > /dev/null
}

bitbucket_pullrequest_progress_comment() {
  # $1: status (success, failure or pending)
  # $2: hash of merge commit
  # $3: hash of source commit
  # $4: hash of target commit
  build_url="$ATC_EXTERNAL_URL/teams/$BUILD_TEAM_NAME/pipelines/$BUILD_PIPELINE_NAME/jobs/$BUILD_JOB_NAME/builds/$BUILD_NAME"
  build_status_pre="[*Build"
  build_status_post="* **${BUILD_PIPELINE_NAME}-${BUILD_JOB_NAME}** for $2"
  if [ "$2" == "$3" ]; then
    build_status_post+=" into $4]"
  else
    build_status_post="] $3 into $4"
  fi
  build_result_pre=" \n\n **["
  build_result_post="]($build_url)** - Build #$BUILD_NAME"

  case "$1" in
    success)
      echo "${build_status_pre}Finished${build_status_post}${build_result_pre}✓ BUILD SUCCESS${build_result_post}" ;;
    failure)
      echo "${build_status_pre}Finished${build_status_post}${build_result_pre}✕ BUILD FAILED${build_result_post}" ;;
    pending)
      echo "${build_status_pre}Started${build_status_post}${build_result_pre}&#8987; BUILD IN PROGRESS${build_result_post}" ;;
  esac
}

bitbucket_pullrequest_commit_status() {
  # $1: host
  # $2: commit
  # $3: data
  # $4: netrc file (default: $HOME/.netrc)
  log "Setting pull request status $2"
  bitbucket_request "$1" "commits/$2" "" "$3" "rest/build-status/1.0" "$5"
}

bitbucket_pullrequest_add_comment_status() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: pullrequest id
  # $5: comment
  # $6: netrc file (default: $HOME/.netrc)
  log "Adding pull request comment for status on #$4 for $2/$3"
  bitbucket_request "$1" "projects/$2/repos/$3/pull-requests/$4/comments" "" "{\"text\": \"$5\" }" "" "$6"
}

bitbucket_pullrequest_update_comment_status() {
  # $1: host
  # $2: project
  # $3: repository id
  # $4: pullrequest id
  # $5: comment
  # $6: comment id
  # $7: comment version
  # $8: netrc file (default: $HOME/.netrc)
  log "Updating pull request comment (id: $6) for status on #$4 for $2/$3"
  bitbucket_request "$1" "projects/$2/repos/$3/pull-requests/$4/comments/$6" "" "{\"text\": \"$5\", \"version\": \"$7\" }" "" "$8" "PUT"
}
