FROM gliderlabs/alpine:edge

RUN apk --update add \
  ca-certificates \
  bash \
  jq \
  oniguruma \
  curl

ADD assets/ /opt/resource/
RUN chmod +x /opt/resource/*
