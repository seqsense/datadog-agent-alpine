FROM alpine:3.13 as systemd-builder

RUN apk add --no-cache \
    autoconf \
    bash \
    cmake \
    coreutils \
    g++ \
    gcc \
    git \
    gperf \
    libcap-dev \
    libseccomp-dev \
    lz4-dev \
    make \
    meson \
    musl-dev \
    musl-libintl \
    ninja \
    patch \
    util-linux-dev \
    xz-dev

ARG SYSTEMD_VERSION=v246.6
ARG SYSTEMD_LIB_VERSION=0.29.0
ARG OPENEMBEDDED_CORE_SHA=3325992e66e8fbd80292beb4b0ffd50beca138d8

ENV CFLAGS=-Os
WORKDIR /work/systemd

RUN cd /work \
  && git clone --depth=1 -b ${SYSTEMD_VERSION} https://github.com/systemd/systemd-stable.git systemd \
  && git clone --depth=1000 https://github.com/openembedded/openembedded-core.git \
  && (cd openembedded-core && git checkout ${OPENEMBEDDED_CORE_SHA}) \
  && cp openembedded-core/meta/recipes-core/systemd/systemd/*.patch systemd/

RUN ls -1 *.patch | xargs -n1 patch -p1 -i
RUN ./configure \
    -Dgshadow=false \
    -Didn=false \
    -Dutmp=false
RUN ninja -C build libsystemd.so.${SYSTEMD_LIB_VERSION}
RUN cp $(find build -name "libsystemd.so*" -type f) /usr/local/lib/

RUN strip -s /usr/local/lib/libsystemd.so*


# ===========================
FROM golang:1.15-alpine3.12 AS agent-builder

RUN apk add --no-cache \
    ca-certificates \
    cmake \
    curl \
    gcc \
    g++ \
    git \
    libexecinfo-dev \
    libffi-dev \
    make \
    musl-dev \
    patch \
    py3-pip \
    py3-requests \
    py3-toml \
    py3-wheel \
    py3-yaml \
    python3-dev \
  && python3 -m pip install \
    docker==3.7.3 \
    invoke==1.4.1 \
    reno==3.1.0

ARG DATADOG_VERSION=7.24.1
# datadog-agent has both branch and tag of the version. refs/tags/version must be checked-out.
RUN git clone --depth=1 https://github.com/DataDog/datadog-agent.git /build/datadog-agent \
  && cd /build/datadog-agent \
  && git fetch --depth=1 origin refs/tags/${DATADOG_VERSION}:refs/tags/${DATADOG_VERSION} \
  && git checkout refs/tags/${DATADOG_VERSION}

WORKDIR /build/datadog-agent

RUN invoke deps

ENV CGO_CFLAGS="-Os -I/build/datadog-agent/dev/include" \
  CGO_LDFLAGS="-L/build/datadog-agent/dev/lib" \
  GOFLAGS="-ldflags=-w -ldflags=-s"

RUN invoke rtloader.make \
    --python-runtimes=3 \
    --cmake-options="\
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_CXX_FLAGS=-Os \
      -DCMAKE_C_FLAGS=-Os" \
  && invoke rtloader.install

RUN strip -s /build/datadog-agent/dev/lib/*.so

COPY --from=systemd-builder /work/systemd/src/systemd/ /usr/include/systemd/

RUN invoke agent.build \
    --python-runtimes=3 \
    --exclude-rtloader \
    --build-exclude=jmx,kubeapiserver,gce,ec2

RUN mkdir -p /agent-bin \
  && touch /agent-bin/.keep

ARG ENABLE_PROCESS_AGENT=0
RUN if [ ${ENABLE_PROCESS_AGENT} -eq 1 ]; then \
    invoke process-agent.build \
      --python-runtimes=3; \
    mv bin/process-agent/process-agent /agent-bin/; \
  fi

ARG ENABLE_SECURITY_AGENT=0
RUN if [ ${ENABLE_SECURITY_AGENT} -eq 1 ]; then \
    invoke security-agent.build; \
    mv bin/security-agent/security-agent /agent-bin/; \
  fi

ARG ENABLE_TRACE_AGENT=0
RUN if [ ${ENABLE_TRACE_AGENT} -eq 1 ]; then \
    invoke trace-agent.build \
      --python-runtimes=3; \
    mv bin/trace-agent/trace-agent /agent-bin/; \
  fi

ARG ENABLE_SYSTEM_PROBE=0
RUN if [ ${ENABLE_SYSTEM_PROBE} -eq 1 ]; then \
    apk add --no-cache \
      bcc-dev \
      clang \
      linux-virt-dev \
      linux-headers \
      libbpf-dev \
      llvm10; \
    invoke system-probe.build \
      --python-runtimes=3; \
    mv bin/system-probe/system-probe /agent-bin/; \
  fi

RUN mkdir -p \
    /opt/datadog-agent/bin/agent/dist \
    /opt/datadog-agent/run \
    /etc/datadog-agent \
  && touch /opt/datadog-agent/requirements-agent-release.txt \
  && touch /opt/datadog-agent/final_constraints-py3.txt

RUN cp /build/datadog-agent/bin/agent/agent /opt/datadog-agent/bin/agent/agent
RUN cp -r \
  /build/datadog-agent/bin/agent/dist/checks \
  /build/datadog-agent/bin/agent/dist/config.py \
  /build/datadog-agent/bin/agent/dist/utils \
  /build/datadog-agent/bin/agent/dist/views \
  /opt/datadog-agent/bin/agent/dist/

RUN cp -r /build/datadog-agent/bin/agent/dist/conf.d /etc/datadog-agent/conf.d/
RUN cp \
  /build/datadog-agent/Dockerfiles/agent/datadog-docker.yaml \
  /build/datadog-agent/Dockerfiles/agent/datadog-ecs.yaml \
  /build/datadog-agent/bin/agent/dist/system-probe.yaml \
  /etc/datadog-agent/
RUN cp \
  /build/datadog-agent/bin/agent/dist/datadog.yaml \
  /etc/datadog-agent/datadog.yaml.example

# Remove unused configs
RUN rm -rf \
  /etc/datadog-agent/conf.d/apm.yaml.default \
  /etc/datadog-agent/conf.d/process_agent.yaml.default \
  /etc/datadog-agent/conf.d/winproc.d \
  /etc/datadog-agent/conf.d/jmx.d \
  /etc/datadog-agent/conf.d/kubernetes_apiserver.d


# ===========================
FROM alpine:3.13 AS datadog-agent

ARG ENABLE_SYSTEM_PROBE=1

RUN echo "@v3.13 http://dl-cdn.alpinelinux.org/alpine/v3.13/main" >> /etc/apk/repositories \
  && echo "@v3.13 http://dl-cdn.alpinelinux.org/alpine/v3.13/community" >> /etc/apk/repositories \
  && apk add \
    bash \
    ca-certificates \
    coreutils \
    libexecinfo \
    libffi \
    libgcc \
    libressl \
    libseccomp \
    libstdc++ \
    lz4-libs \
    py3-pip \
    py3-prometheus-client \
    py3-psutil \
    py3-requests \
    py3-requests-toolbelt \
    py3-toml \
    py3-wheel \
    py3-yaml \
    python3 \
    s6 \
    s6-overlay@v3.13 \
    xz \
  && if [ ${ENABLE_SYSTEM_PROBE} -eq 1 ]; then \
      apk add --no-cache \
        bcc \
        libbpf; \
    fi \
  && apk add --virtual .build-deps \
    gcc \
    musl-dev \
    python3-dev \
  && python3 -m pip install \
    # binary is used by datadog_checks.base but not specified as a dependency \
    binary \
    docker==3.7.3 \
  && apk del .build-deps \
  && sed '/^@edge /d' -i /etc/apk/repositories \
  && rm -f /var/cache/apk/* \
  && find /usr -name "*.pyc" -delete \
  && find /usr -name "__pycache__" -delete

RUN mkdir -p \
    /checks.d \
    /conf.d \
    /opt/datadog-agent \
    /opt/datadog-agent/run \
    /var/log/datadog \
  && touch /opt/datadog-agent/requirements-agent-release.txt \
  && touch /opt/datadog-agent/final_constraints-py3.txt \
  && ln -s /usr /opt/datadog-agent/embedded

COPY --from=systemd-builder /usr/local/lib/libsystemd* /usr/lib/

# Install datadog agent
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/s6-services /etc/services.d/
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/entrypoint  /etc/cont-init.d/
COPY --from=agent-builder \
  /build/datadog-agent/Dockerfiles/agent/probe.sh \
  /build/datadog-agent/Dockerfiles/agent/initlog.sh \
  /build/datadog-agent/Dockerfiles/agent/secrets-helper/readsecret.py \
  /
COPY --from=agent-builder /build/datadog-agent/dev/lib/* /usr/lib/
COPY --from=agent-builder /etc/datadog-agent             /etc/datadog-agent/
COPY --from=agent-builder /opt/datadog-agent             /opt/datadog-agent/
COPY --from=agent-builder /agent-bin/*                   /usr/bin/

# Disable omitted agents
RUN if [ ! -f /usr/bin/process-agent   ]; then rm -rf /etc/services.d/process;  fi \
  && if [ ! -f /usr/bin/security-agent ]; then rm -rf /etc/services.d/security; fi \
  && if [ ! -f /usr/bin/trace-agent    ]; then rm -rf /etc/services.d/trace;    fi \
  && if [ ! -f /usr/bin/system-probe   ]; then rm -rf /etc/services.d/sysprobe; fi

ENV DOCKER_DD_AGENT=true \
    DD_PYTHON_VERSION=3 \
    PATH=/opt/datadog-agent/bin/agent/:/opt/datadog-agent/embedded/bin:$PATH \
    S6_KEEP_ENV=1 \
    S6_LOGGING=0 \
    S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
    S6_READ_ONLY_ROOT=1

ARG INTEGRATIONS_CORE="\
  btrfs \
  disk \
  ssh_check \
  statsd \
  system_core \
  system_swap"

ARG DATADOG_INTEGRATIONS_CORE_VERSION=7.24.0
RUN apk add --force-broken-world --virtual .build-deps git \
  && git clone --depth=1 https://github.com/DataDog/integrations-core.git /tmp/integrations-core \
  && cd /tmp/integrations-core \
  && git fetch --depth=1 origin refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION}:refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && git checkout refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && python3 -m pip install \
    ./datadog_checks_base \
    $(echo ${INTEGRATIONS_CORE} | xargs -n1 echo | sed 's|^|./|') \
  && apk del --force-broken-world .build-deps \
  && cd / && rm -rf /tmp/integrations-core \
  && rm -f /var/cache/apk/* \
  && find /usr -name "*.pyc" -delete \
  && find /usr -name "__pycache__" -delete

EXPOSE 8125/udp 8126/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=2 \
  CMD ["/probe.sh"]

CMD ["/init"]
