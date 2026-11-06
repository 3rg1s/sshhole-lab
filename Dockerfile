FROM alpine:3.23 AS build

RUN apk add --no-cache --virtual .build-deps \
      build-base linux-headers zlib-dev openssl-dev openssl curl tar
WORKDIR /tmp/src
RUN curl -fsSLO https://ftp.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-10.2p1.tar.gz \
    && actual="$(openssl dgst -sha256 -binary openssh-10.2p1.tar.gz | openssl base64 -A)" \
    && test "$actual" = 'zMQsBBmTeVkmP6Hb0W2vwYxWuYTANWLSk3zlamD3mLI=' \
    && tar -xzf openssh-10.2p1.tar.gz
WORKDIR /tmp/src/openssh-10.2p1
RUN ./configure \
      --prefix=/usr \
      --sysconfdir=/etc/ssh \
      --with-privsep-path=/var/empty \
      --without-pam \
      --without-selinux \
    && make -j"$(getconf _NPROCESSORS_ONLN)" \
    && make install

FROM alpine:3.23 AS runtime
RUN apk add --no-cache openssl zlib \
    && mkdir -p /run/sshd /var/empty /etc/ssh \
    && chmod 755 /var/empty
COPY --from=build /usr/sbin/sshd /usr/sbin/sshd
COPY --from=build /usr/bin/ssh-keygen /usr/bin/ssh-keygen
COPY --from=build /usr/libexec/sshd-session /usr/libexec/sshd-session
COPY --from=build /usr/libexec/sshd-auth /usr/libexec/sshd-auth
COPY sshd_config /etc/ssh/sshd_config
COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh \
    && adduser -D -h /home/auditdirectory -s /bin/sh auditdirectory \
    && sed -i '/^auditdirectory:/d' /etc/shadow \
    && awk -F: 'BEGIN { OFS = ":" } $1 == "auditdirectory" { $2 = "*" } { print }' /etc/passwd > /tmp/passwd \
    && cat /tmp/passwd > /etc/passwd \
    && rm /tmp/passwd \
    && mkdir -p /home/auditdirectory \
    && chown auditdirectory:auditdirectory /home/auditdirectory \
    && adduser -D -h /nonexistent -s /sbin/nologin audit-salt \
    && salt_password="$(openssl rand -base64 48)" \
    && salt_hash="$(openssl passwd -6 -salt sshholelab "$salt_password")" \
    && unset salt_password \
    && sed -i "s|^audit-salt:[^:]*:|audit-salt:${salt_hash}:|" /etc/shadow
EXPOSE 2222
ENTRYPOINT ["/entrypoint.sh"]

FROM alpine:3.23 AS verify-client
RUN apk add --no-cache openssl zlib
COPY --from=build /usr/bin/ssh /usr/bin/ssh
COPY verify-lab.sh /verify-lab.sh
RUN chmod 755 /verify-lab.sh
ENTRYPOINT ["/verify-lab.sh"]
