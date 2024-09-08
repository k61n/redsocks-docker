# Alpine with glibc arm64
FROM alpine:latest as alpine-glibc-arm64
ENV LANG=C.UTF-8
RUN apk add --no-cache wget && \
    wget \
        https://github.com/Rjerk/alpine-pkg-glibc/releases/download/2.30-r0-arm64/glibc-2.30-r0.apk \
        https://github.com/Rjerk/alpine-pkg-glibc/releases/download/2.30-r0-arm64/glibc-bin-2.30-r0.apk \
        https://github.com/Rjerk/alpine-pkg-glibc/releases/download/2.30-r0-arm64/glibc-i18n-2.30-r0.apk && \
    mv /etc/nsswitch.conf /etc/nsswitch.conf.bak && \
    apk add --no-cache --force-overwrite --allow-untrusted \
        glibc-2.30-r0.apk \
        glibc-bin-2.30-r0.apk \
        glibc-i18n-2.30-r0.apk && \
    mv /etc/nsswitch.conf.bak /etc/nsswitch.conf && \
    (/usr/glibc-compat/bin/localedef --force --inputfile POSIX --charmap UTF-8 "$LANG" || true) && \
    echo "export LANG=$LANG" > /etc/profile.d/locale.sh && \
    apk del glibc-i18n && \
    rm "/root/.wget-hsts" && \
    rm glibc-2.30-r0.apk glibc-bin-2.30-r0.apk glibc-i18n-2.30-r0.apk

# Compile redsocks 
FROM alpine-glibc-arm64 AS redsocks
RUN mkdir /tmp/redsocks
WORKDIR /tmp/redsocks
RUN apk add gcc musl-dev linux-headers libevent-dev git make upx
RUN git clone https://github.com/darkk/redsocks "/tmp/redsocks"
RUN make ENABLE_STATIC=true

RUN upx -9 /tmp/redsocks/redsocks

# Compile dnscrypt
FROM golang:alpine as dnscrypt
ENV RELEASE_TAG 2.0.42
RUN apk --no-cache add git upx && \
    git clone https://github.com/DNSCrypt/dnscrypt-proxy /go/src/github.com/DNSCrypt/ && \
    cd /go/src/github.com/DNSCrypt/dnscrypt-proxy && \
    git checkout tags/${RELEASE_TAG} && \
    CGO_ENABLED=0 GOOS=linux go install -a -ldflags '-s -w -extldflags "-static"' -v ./...

RUN upx -9 /go/bin/dnscrypt-proxy

# Main docker
FROM alpine-glibc-arm64
RUN mkdir -p /var/cache/pdnsd
RUN apk add --no-cache libevent iptables
COPY --from=redsocks /tmp/redsocks/redsocks  /usr/local/bin/redsocks
COPY --from=dnscrypt /go/bin/dnscrypt-proxy /usr/local/bin/dnscrypt-proxy

COPY redsocks.tmpl /etc/redsocks.tmpl
COPY whitelist.txt /etc/redsocks-whitelist.txt
COPY redsocks.sh /usr/local/bin/redsocks.sh
COPY redsocks-fw.sh /usr/local/bin/redsocks-fw.sh
COPY dnscrypt-proxy.toml /config/
RUN mkdir /blacklist/ ; touch /blacklist/blacklist.txt

RUN chmod +x /usr/local/bin/redsocks.sh
RUN chmod +x /usr/local/bin/redsocks-fw.sh
ENTRYPOINT ["/usr/local/bin/redsocks.sh"]
