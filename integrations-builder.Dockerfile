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
    python3-dev \
    patchelf \
    rustup

RUN rustup-init -y

RUN git clone --depth=1 https://github.com/DataDog/integrations-core.git /tmp/integrations-core \
  && cd /tmp/integrations-core \
  && git fetch --depth=1 origin refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION}:refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && git checkout refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && if [ "$(apk --print-arch)" != x86_64 ]; then \
      sed '/"pytest-memray[>=]/d' -i datadog_checks_dev/pyproject.toml; \
    fi \
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
    "/tmp/integrations-core/datadog_checks_dev[cli]" \
    "/tmp/integrations-core/ddev" \
  && rm -rf /tmp/integrations-core

# note: removed packages from datadog_checks_dev/pyproject.toml on non-x86_64
#   pytest-memray: memray has no musllinux wheel for aarch64 and requires libdebuginfod to build

CMD ["/bin/sh"]
