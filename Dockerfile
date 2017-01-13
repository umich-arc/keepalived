FROM alpine

ARG BUILD_DATE
ARG VCS_REF
ARG VERSION

LABEL architecture="x86_64"                       \
      build-date="$BUILD_DATE"                    \
      license="MIT"                               \
      name="arcts/keepalived"                     \
      summary="Alpine based keepalived container" \
      version="$VERSION"                          \
      vcs-ref="$VCS_REF"                          \
      vcs-type="git"                              \
      vcs-url="https://github.com/arc-ts/keepalived"


RUN apk add --no-cache \
    bash       \
    curl       \
    ipvsadm    \
    iproute2   \
    keepalived \
 && rm /etc/keepalived/keepalived.conf

COPY /skel /

RUN chmod +x init.sh

CMD ["./init.sh"]
