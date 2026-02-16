# syntax=docker/dockerfile:1

FROM alpine:edge

RUN set -eu && \
    apk --no-cache add \
    tini \
    bash \
    gocryptfs \
    fuse3 \
    inotify-tools \
    rsync \
    samba \
    samba-winbind \
    samba-winbind-clients \
    samba-libnss-winbind \
    samba-winbind-krb5-locator \
    openldap-clients \
    tzdata \
    shadow && \
    echo "user_allow_other" > /etc/fuse.conf && \
    chmod 644 /etc/fuse.conf && \
    addgroup -S smb && \
    rm -f /etc/samba/smb.conf && \
    rm -rf /tmp/* /var/cache/apk/*

COPY --chmod=755 samba.sh /usr/bin/samba.sh
COPY --chmod=664 smb.conf /etc/samba/smb.default

VOLUME /encrypted /storage /snapshots
EXPOSE 139 445

ENV NAME="Data"
ENV USER="samba"
ENV PASS="secret"

ENV UID=1000
ENV GID=1000
ENV RW=true
ENV SNAPSHOT_DIR="/snapshots"

HEALTHCHECK --interval=60s --timeout=15s CMD smbclient --configfile=/etc/samba.conf -L \\localhost -U % -m SMB3

ENTRYPOINT ["/sbin/tini", "--", "/usr/bin/samba.sh"]
