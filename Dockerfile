FROM alpine:3.7

# # TODO: Docker Hub does not allow environment variables as Docker Cloud Does.
# # For now, assume master = current SHA
ENV SOURCE_BRANCH master

RUN set -ex \
    && apk add --no-cache perl perl-utils perl-dev make build-base openssl openssl-dev expat expat-dev \
    && wget -O - https://github.com/evernote/serge/archive/${SOURCE_BRANCH}.tar.gz | tar zxf - \
    && mv /serge-* /serge \
    && yes | cpan App::cpanminus \
    && cpanm --no-wget --installdeps /serge \
    && rm -rf /root/.cpan* /usr/local/share/man \
    && mkdir -p /data \
    && cp /serge/doc/sample.serge /data \
    && apk del -f --purge make build-base openssl-dev expat-dev

ENV PATH="/serge/bin:${PATH}"
VOLUME /data
WORKDIR /data
ENTRYPOINT /serge/bin/serge
