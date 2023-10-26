ARG DATADOG_MAJOR_VERSION
ARG BASE_IMAGE_PREFIX=
FROM ${BASE_IMAGE_PREFIX}datadog-agent:${DATADOG_MAJOR_VERSION}-alpine

WORKDIR /wheels

RUN apk add --no-cache \
    gcc \
    g++ \
    git \
    libffi-dev \
    libunwind-dev \
    lz4-dev \
    openssl-dev \
    make \
    musl-dev \
    py3-aiohttp \
    py3-bcrypt \
    py3-cryptography \
    py3-distlib \
    py3-packaging \
    py3-pynacl \
    py3-pip \
    py3-regex \
    python3-dev \
    patch \
    patchelf \
    rustup

RUN rustup-init -y

COPY install-ddev.patch /
RUN git clone --depth=1 https://github.com/DataDog/integrations-core.git /tmp/integrations-core \
  && cd /tmp/integrations-core \
  && git fetch --depth=1 origin refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION}:refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && git checkout refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && patch -p1 < /install-ddev.patch \
  && version() { apk info $1 2> /dev/null | sed -n 's/\S\+-\([0-9\.]\+\)-r[0-9]\+ description:/\1/p'; } \
  && . ${HOME}/.cargo/env \
  && python3 -m pip install \
    aiohttp==$(version py3-aiohttp) \
    bcrypt==$(version py3-bcrypt) \
    cryptography==$(version py3-cryptography) \
    distlib==$(version py3-distlib) \
    packaging==$(version py3-packaging) \
    pynacl==$(version py3-pynacl) \
    pip==$(version py3-pip) \
    regex==$(version py3-regex) \
    "/tmp/integrations-core/datadog_checks_dev[cli]" \
  && rm -rf /tmp/integrations-core

CMD ["/bin/sh"]
