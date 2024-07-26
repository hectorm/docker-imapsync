# syntax=docker/dockerfile:1
m4_changequote([[, ]])

##################################################
## "build" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:24.04]], [[FROM docker.io/ubuntu:24.04]]) AS build

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		cpanminus \
		curl \
		libauthen-ntlm-perl \
		libcgi-pm-perl \
		libcrypt-openssl-rsa-perl \
		libdata-uniqid-perl \
		libdist-checkconflicts-perl \
		libencode-imaputf7-perl \
		libfile-copy-recursive-perl \
		libfile-tail-perl \
		libhtml-parser-perl \
		libio-socket-inet6-perl \
		libio-socket-ssl-perl \
		libio-tee-perl \
		libjson-webtoken-perl \
		libmail-imapclient-perl \
		libmodule-implementation-perl \
		libmodule-scandeps-perl \
		libnet-server-perl \
		libpackage-stash-perl \
		libpackage-stash-xs-perl \
		libpar-packer-perl \
		libparse-recdescent-perl \
		libproc-processtable-perl \
		libreadonly-perl \
		libregexp-common-perl \
		libsys-meminfo-perl \
		libterm-readkey-perl \
		libtest-deep-perl \
		libtest-fatal-perl \
		libtest-mock-guard-perl \
		libtest-mockobject-perl \
		libtest-nowarnings-perl \
		libtest-pod-perl \
		libtest-requires-perl \
		libtest-warn-perl \
		libunicode-string-perl \
		liburi-perl \
		libwww-perl \
		make \
		patch \
		procps \
	&& rm -rf /var/lib/apt/lists/*

# Build Imapsync
ARG IMAPSYNC_VERSION=2.264
ARG IMAPSYNC_TARBALL_URL=https://imapsync.lamiral.info/dist/imapsync-${IMAPSYNC_VERSION}.tgz
ARG IMAPSYNC_TARBALL_CHECKSUM=14469e2de0d8deba6195a63e388bc38a6b7000ff12220912bf8f01a5673d6c7d
RUN curl -Lo /tmp/imapsync.tgz "${IMAPSYNC_TARBALL_URL:?}"
RUN printf '%s' "${IMAPSYNC_TARBALL_CHECKSUM:?}  /tmp/imapsync.tgz" | sha256sum -c
RUN mkdir /tmp/imapsync/
WORKDIR /tmp/imapsync/
RUN tar -xzf /tmp/imapsync.tgz --strip-components=1
COPY --chown=root:root ./patches/imapsync/ /tmp/patches/imapsync/
RUN find /tmp/patches/imapsync/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /tmp/patches/imapsync/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'
RUN for f in /tmp/patches/imapsync/*.patch; do patch -p1 < "${f:?}"; done
RUN ./INSTALL.d/prerequisites_imapsync
RUN PATH="${PATH}:${PWD}" pp -x -o ./imapsync.cgi ./imapsync
RUN ./imapsync.cgi --version
WORKDIR /tmp/imapsync/X/
RUN ln -sf ./imapsync_form_extra.html ./index.html
RUN rm -f ./imapsync_current.txt && touch ./imapsync_current.txt

##################################################
## "main" stage
##################################################

m4_ifdef([[CROSS_ARCH]], [[FROM docker.io/CROSS_ARCH/ubuntu:24.04]], [[FROM docker.io/ubuntu:24.04]]) AS main

# Install system packages
RUN export DEBIAN_FRONTEND=noninteractive \
	&& apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		catatonit \
		h2o \
		perl \
		procps \
	&& rm -rf /var/lib/apt/lists/*

# Copy Imapsync build
COPY --from=build --chown=root:root /tmp/imapsync/imapsync.cgi /opt/imapsync/cgi/
COPY --from=build --chown=root:root /tmp/imapsync/X/ /opt/imapsync/www/
RUN find /opt/imapsync/cgi/ -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /opt/imapsync/www/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /opt/imapsync/www/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'

# Copy h2o config
COPY --chown=root:root ./config/h2o/ /etc/h2o/
RUN find /etc/h2o/ -type d -not -perm 0755 -exec chmod 0755 '{}' ';'
RUN find /etc/h2o/ -type f -not -perm 0644 -exec chmod 0644 '{}' ';'

# Create unprivileged user
RUN userdel -rf "$(id -nu 1000)" && useradd -u 1000 -g 0 -s "$(command -v bash)" -m imapsync

# Drop root privileges
USER imapsync:root

# Run Imapsync tests
RUN --network=none --mount=type=tmpfs,target=/tmp/ cd /tmp/ && /opt/imapsync/cgi/imapsync.cgi --tests

# Web server port
EXPOSE 8080/tcp

ENTRYPOINT ["/usr/bin/catatonit", "--"]
CMD ["h2o", "--mode", "worker", "--conf", "/etc/h2o/h2o.conf"]
