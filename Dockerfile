ARG ALPINE_VERSION=3.20
ARG GOLANG_VERSION=1.24

# ===========================
FROM alpine:${ALPINE_VERSION} as systemd-builder

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
    py3-jinja2 \
    rsync \
    util-linux-dev \
    xz-dev \
    zstd-dev

ARG SYSTEMD_VERSION=v254.4
ARG SYSTEMD_LIB_VERSION=0.37.0
ARG OPENEMBEDDED_CORE_SHA=8063bcb2d4fcfeded5edac3b0895151e8dc8bf0f

ENV CFLAGS=-Os
WORKDIR /work/systemd

RUN cd /work \
  && git clone --depth=1 -b ${SYSTEMD_VERSION} https://github.com/systemd/systemd-stable.git systemd \
  && git clone --depth=10000 https://github.com/openembedded/openembedded-core.git \
  && (cd openembedded-core && git checkout ${OPENEMBEDDED_CORE_SHA}) \
  && cp openembedded-core/meta/recipes-core/systemd/systemd/*.patch systemd/

ENV CFLAGS=-D__UAPI_DEF_ETHHDR=0

RUN ls -1 *.patch | xargs -n1 patch -p1 -i
RUN ./configure \
    -Dgshadow=false \
    -Didn=false \
    -Dutmp=false
RUN ninja -C build libsystemd.so.${SYSTEMD_LIB_VERSION}
RUN cp -v $(find build -name "libsystemd.so.${SYSTEMD_LIB_VERSION}" -type f) /usr/local/lib/
RUN strip -s /usr/local/lib/libsystemd.so.${SYSTEMD_LIB_VERSION}


# ===========================
FROM golang:${GOLANG_VERSION}-alpine${ALPINE_VERSION} AS agent-builder

RUN apk add --no-cache \
    aws-cli \
    bash \
    ca-certificates \
    cmake \
    curl \
    g++ \
    gcc \
    git \
    libffi-dev \
    make \
    musl-dev \
    patch \
    py3-boto3 \
    py3-botocore \
    py3-docker-py \
    py3-dulwich \
    py3-isort \
    py3-packaging \
    py3-pip \
    py3-prompt_toolkit \
    py3-requests \
    py3-ruamel.yaml \
    py3-semver \
    py3-toml \
    py3-urllib3=~1 \
    py3-wheel \
    py3-yaml \
    python3-dev

ARG DATADOG_VERSION=7.67.0
# datadog-agent has both branch and tag of the version. refs/tags/version must be checked-out.
RUN git clone --depth=1 https://github.com/DataDog/datadog-agent.git /build/datadog-agent \
  && cd /build/datadog-agent \
  && git fetch --depth=1 origin refs/tags/${DATADOG_VERSION}:refs/tags/${DATADOG_VERSION} \
  && git checkout refs/tags/${DATADOG_VERSION}

WORKDIR /build/datadog-agent

ARG DATADOG_DDA_VERSION=v0.17.0
RUN python3 -m pip install "dda==${DATADOG_DDA_VERSION}" --break-system-packages \
  && dda -v self dep sync -f legacy-tasks
ENV GOWORK=off

ARG CI_ONLY_DEPS=" \
  codeowners \
  docker-squash \
  reno \
"
ARG SYSTEM_PYTHON_DEPS=" \
  awscli \
  boto3 \
  botocore \
  docker \
  dulwich \
  isort \
  packaging \
  pyyaml \
  requests \
  ruamel.yaml \
  semver \
  toml \
  urllib3 \
  wheel \
"

RUN invoke deps

ENV CGO_CFLAGS="-Os -I/build/datadog-agent/dev/include" \
  CGO_LDFLAGS="-L/build/datadog-agent/dev/lib" \
  GOFLAGS="-ldflags=-w -ldflags=-s"

RUN invoke rtloader.make \
    --cmake-options="\
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_CXX_FLAGS=-Os \
      -DCMAKE_C_FLAGS=-Os" \
  && invoke rtloader.install

RUN strip -s /build/datadog-agent/dev/lib/*.so

COPY --from=systemd-builder /work/systemd/src/systemd/ /usr/include/systemd/

RUN invoke agent.build \
    --no-glibc \
    --exclude-rtloader \
    --build-exclude=jmx,kubeapiserver,ec2,orchestrator

RUN mkdir -p /agent-bin \
  && mkdir -p /agent-embedded \
  && touch /agent-bin/.keep

ARG ENABLE_PROCESS_AGENT=0
RUN set -eu; \
  if [ ${ENABLE_PROCESS_AGENT} -eq 1 ]; then \
    invoke process-agent.build; \
    mv bin/process-agent/process-agent /agent-bin/; \
  fi

ARG ENABLE_SECURITY_AGENT=0
RUN set -eu; \
  if [ ${ENABLE_SECURITY_AGENT} -eq 1 ]; then \
    invoke security-agent.build; \
    mv bin/security-agent/security-agent /agent-bin/; \
  fi

ARG ENABLE_TRACE_AGENT=0
RUN set -eu; \
  if [ ${ENABLE_TRACE_AGENT} -eq 1 ]; then \
    invoke trace-agent.build; \
    mv bin/trace-agent/trace-agent /agent-bin/; \
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
FROM alpine:${ALPINE_VERSION} AS datadog-agent

RUN apk add \
    aws-cli \
    bash \
    ca-certificates \
    coreutils \
    libffi \
    libgcc \
    libseccomp \
    libstdc++ \
    lz4-libs \
    openssl-dev \
    py3-cryptography \
    py3-jellyfish \
    py3-python-gssapi \
    py3-packaging \
    py3-pip \
    py3-prometheus-client \
    py3-protobuf \
    py3-psutil \
    py3-pysocks \
    py3-requests \
    py3-requests-toolbelt \
    py3-simplejson \
    py3-six \
    py3-wheel \
    py3-wrapt \
    py3-yaml \
    python3 \
    xz-libs \
    zstd-libs \
  && rm -f /var/cache/apk/* \
  && find /usr -name "*.pyc" -delete \
  && find /usr -name "__pycache__" -delete

RUN echo -e "[global]\nbreak-system-packages = true" >> /etc/pip.conf

ARG S6_OVERLAY_VERSION=2.1.0.2
RUN wget https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-amd64.tar.gz \
  && tar xzf /s6-overlay-amd64.tar.gz \
  && rm /s6-overlay-amd64.tar.gz

RUN mkdir -p \
    /checks.d \
    /conf.d \
    /opt/datadog-agent \
    /opt/datadog-agent/run \
    /var/log/datadog \
  && touch /opt/datadog-agent/requirements-agent-release.txt \
  && touch /opt/datadog-agent/final_constraints-py3.txt \
  && ln -s /usr /opt/datadog-agent/embedded

COPY --from=systemd-builder /usr/local/lib/libsystemd.so* /usr/lib/
RUN SYSTEMD_SO=$(find /usr/lib/ -name "libsystemd.so.*.*.*" | head -n1) \
  && ln -s ${SYSTEMD_SO} $(echo ${SYSTEMD_SO} | sed 's/.[0-9]\+$//') \
  && ln -s ${SYSTEMD_SO} $(echo ${SYSTEMD_SO} | sed 's/.[0-9]\+.[0-9]\+$//') \
  && ln -s ${SYSTEMD_SO} $(echo ${SYSTEMD_SO} | sed 's/.[0-9]\+.[0-9]\+.[0-9]\+$//')

# Install datadog agent
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/s6-services /etc/services.d/
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/cont-init.d /etc/cont-init.d/
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/entrypoint.sh /bin/entrypoint.sh
COPY --from=agent-builder /build/datadog-agent/Dockerfiles/agent/entrypoint.d /opt/entrypoints
COPY --from=agent-builder \
  /build/datadog-agent/Dockerfiles/agent/probe.sh \
  /build/datadog-agent/Dockerfiles/agent/initlog.sh \
  /build/datadog-agent/Dockerfiles/agent/secrets-helper/readsecret.py \
  /
COPY --from=agent-builder /build/datadog-agent/dev/lib/* /usr/lib/
COPY --from=agent-builder /etc/datadog-agent             /etc/datadog-agent/
COPY --from=agent-builder /opt/datadog-agent             /opt/datadog-agent/
COPY --from=agent-builder /agent-bin/*                   /usr/bin/
COPY --from=agent-builder /agent-embedded                /usr/

# Disable omitted agents
RUN if [ ! -f /usr/bin/process-agent   ]; then rm -rf /etc/services.d/process;  fi \
  && if [ ! -f /usr/bin/security-agent ]; then rm -rf /etc/services.d/security; fi \
  && if [ ! -f /usr/bin/trace-agent    ]; then rm -rf /etc/services.d/trace;    fi \
  && if [ ! -f /usr/bin/system-probe   ]; then rm -rf /etc/services.d/sysprobe; fi

# Disable otel-agent
RUN rm -rf /etc/services.d/otel

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

ARG DATADOG_INTEGRATIONS_CORE_VERSION=7.67.0
RUN apk add --virtual .build-deps \
    g++ \
    gcc \
    git \
    linux-headers \
    musl-dev \
    python3-dev \
  && git clone --depth=1 https://github.com/DataDog/integrations-core.git /tmp/integrations-core \
  && cd /tmp/integrations-core \
  && git fetch --depth=1 origin refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION}:refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && git checkout refs/tags/${DATADOG_INTEGRATIONS_CORE_VERSION} \
  && for d in \
      botocore \
      cryptography \
      gssapi \
      jellyfish \
      prometheus-client \
      protobuf \
      pysocks \
      pyyaml \
      requests \
      requests_toolbelt \
      simplejson \
      six \
      wheel \
      wrapt \
    ; do \
      sed "/\"$d=/di" -i datadog_checks_base/pyproject.toml; \
    done \
  && python3 -m pip install \
    "./datadog_checks_base[deps, http]" \
    $(echo ${INTEGRATIONS_CORE} | xargs -n1 echo | sed 's|^|./|') \
  && apk del --force-broken-world .build-deps \
  && cd / && rm -rf /tmp/integrations-core \
  && rm -f /var/cache/apk/* \
  && find /usr -name "*.pyc" -delete \
  && find /usr -name "__pycache__" -delete \
  && rm -rf \
    /usr/lib/python*/site-packages/twisted/test \
    /usr/lib/python*/site-packages/docutils

# note: removed packages from datadog_checks_base/pyproject.toml
#   botocore: seems not used at all https://github.com/DataDog/integrations-core/search?q=botocore
#   other packages: installed as Alpine package

# note: removed directories
#   twisted/test: unit test of twisted package
#   docutils: indirect dev dependency

EXPOSE 8125/udp 8126/tcp

HEALTHCHECK --interval=30s --timeout=5s --retries=2 \
  CMD ["/probe.sh"]

ARG DATADOG_VERSION=7.60.1
ENV DATADOG_INTEGRATIONS_CORE_VERSION=${DATADOG_INTEGRATIONS_CORE_VERSION} \
  DATADOG_VERSION=${DATADOG_VERSION}

CMD ["/bin/entrypoint.sh"]
