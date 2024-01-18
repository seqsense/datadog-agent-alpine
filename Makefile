NAME     := datadog-agent

DATADOG_MAJOR_VERSION := 7

ENABLE_PROCESS_AGENT  ?= 0
ENABLE_SECURITY_AGENT ?= 0
ENABLE_TRACE_AGENT    ?= 0

INTEGRATIONS_CORE ?= \
  btrfs \
  disk \
  ssh_check \
  statsd \
  system_core \
  system_swap

TAG_SUFFIX_LIST := \
	$(shell [ $(ENABLE_PROCESS_AGENT)  -eq 1 ] && echo "-proc") \
	$(shell [ $(ENABLE_SECURITY_AGENT) -eq 1 ] && echo "-sec") \
	$(shell [ $(ENABLE_TRACE_AGENT)    -eq 1 ] && echo "-apm")

TAG_SUFFIX := $(shell echo $(TAG_SUFFIX_LIST) | sed 's|[ \t]||g; s|-proc-sec-apm|-all|;')-alpine
TAG        := $(DATADOG_MAJOR_VERSION)$(TAG_SUFFIX)

ifeq ($(shell docker buildx version > /dev/null 2> /dev/null; echo $$?),0)
DOCKER_BUILD_CMD := docker buildx build $(or $(BUILDX_OPTS),--load)
else
DOCKER_BUILD_CMD := docker build
endif

.PHONY: docker-build
docker-build:
	$(DOCKER_BUILD_CMD) \
		--build-arg ENABLE_PROCESS_AGENT=$(ENABLE_PROCESS_AGENT) \
		--build-arg ENABLE_SECURITY_AGENT=$(ENABLE_SECURITY_AGENT) \
		--build-arg ENABLE_TRACE_AGENT=$(ENABLE_TRACE_AGENT) \
		--build-arg INTEGRATIONS_CORE="$(INTEGRATIONS_CORE)" \
		-t $(NAME):$(TAG) .
	@echo $(NAME):$(TAG) is built

.PHONY: docker-build-integrations-builder
docker-build-integrations-builder:
ifeq ($(ENABLE_PROCESS_AGENT)$(ENABLE_SECURITY_AGENT)$(ENABLE_TRACE_AGENT),000)
	$(DOCKER_BUILD_CMD) \
		--build-arg DATADOG_MAJOR_VERSION=$(DATADOG_MAJOR_VERSION) \
		-f integrations-builder.Dockerfile \
		-t $(NAME):$(TAG)-integrations-builder .
	@echo $(NAME):$(TAG)-integrations-builder is built
else
	@echo integrations-builder should be built without optional agents
endif

.PHONY: show-image-tag
show-image-tag:
	@echo "tag=$(NAME):$(TAG)" >> ${GITHUB_OUTPUT}

.PHONY: show-image-full-tag
show-image-full-tag:
	@echo "full_tag=$(NAME):$$(docker run --rm --entrypoint /opt/datadog-agent/bin/agent/agent $(NAME):$(TAG) version -n | cut -f2 -d" ")$(TAG_SUFFIX)" | tee -a ${GITHUB_OUTPUT}

.PHONY: show-image-full-tag-with-alpine-version
show-image-full-tag-with-alpine-version:
	@echo "full_tag_with_alpine_version=$(NAME):$$(docker run --rm --entrypoint /opt/datadog-agent/bin/agent/agent $(NAME):$(TAG) version -n | cut -f2 -d" ")$(TAG_SUFFIX)$$(docker run -it --rm --entrypoint sh $(NAME):$(TAG) -c '. /etc/os-release; echo $${VERSION_ID} | head -n1 | cut -d"." -f1-2')" | tee -a ${GITHUB_OUTPUT}
