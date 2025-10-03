ARG ARCH=
FROM ${ARCH}alpine AS build
ARG PUID=1000
ARG GUID=1001
ARG UNBOUND_VERSION="1.24.0"

RUN apk add -q --no-cache  \
    wget \
    ca-certificates \
    build-base \
    libressl-dev \
    libressl \
    expat-static \
    expat-dev \
    libcap-static \
    libcap-dev \
    bison \
    flex \
    hiredis-dev \
    bind-tools

WORKDIR /unbound_build

RUN wget -nv https://nlnetlabs.nl/downloads/unbound/unbound-latest.tar.gz \
    && tar xzf unbound-latest.tar.gz

WORKDIR /unbound_build/unbound-$UNBOUND_VERSION

RUN ./configure --with-libhiredis --disable-gtk-doc --disable-gtk-doc-html --disable-doc --disable-docs --disable-documentation --with-xmlto=no --with-fop=no --disable-dependency-tracking --enable-ipv6 --disable-nls --disable-static --disable-rpath --disable-debug --with-conf-file=/etc/unbound/unbound.conf --with-pidfile=/var/run/unbound.pid --with-rootkey-file=/etc/unbound/root.key --enable-tfo-server --with-ssl --enable-tfo-client --disable-flto --with-run-dir=/var/run/unbound --enable-fully-static --enable-static

RUN make -j \
    && make install -j \
    && strip unbound \
    && strip unbound-control \
    # Exit code 1 if root anchor is created else if it exists 0
    && /unbound_build/unbound-$UNBOUND_VERSION/unbound-anchor || : \
    && ln -s /usr/bin/libressl /usr/bin/openssl \
    && mkdir /etc/unbound/unbound-control-keys \
    && /unbound_build/unbound-$UNBOUND_VERSION/unbound-control-setup -d /etc/unbound/unbound-control-keys \
    && mkdir /var/run/unbound \
    && wget -nv -O /etc/unbound/root.hints https://www.internic.net/domain/named.root \
    && addgroup unbound -g ${GUID} \
    && adduser \
    --disabled-password \
    --no-create-home \
    -u ${PUID} \
    -G unbound \
    unbound

FROM scratch
ARG UNBOUND_VERSION

COPY --from=build /etc/passwd /etc/passwd
COPY --from=build /etc/group /etc/group

USER unbound

COPY --chown=unbound:unbound --from=build /etc/unbound /etc/unbound
COPY --chown=unbound:unbound --from=build /var/run/unbound /var/run/unbound

COPY --chown=unbound:unbound --from=build /unbound_build/unbound-$UNBOUND_VERSION/unbound /usr/bin/unbound
COPY --chown=unbound:unbound --from=build /unbound_build/unbound-$UNBOUND_VERSION/unbound-control /usr/bin/unbound-control
# For healthcheck
COPY --chown=unbound:unbound --from=build /unbound_build/unbound-$UNBOUND_VERSION/unbound-host /usr/bin/unbound-host

COPY --chown=unbound:unbound ./unbound.conf /etc/unbound/

ENV PATH=/usr/bin:${PATH}
