NAME     := datadog-agent

DATADOG_MAJOR_VERSION := 7

ENABLE_PROCESS_AGENT  ?= 0
ENABLE_SECURITY_AGENT ?= 0
ENABLE_TRACE_AGENT    ?= 0
ENABLE_SYSTEM_PROBE   ?= 0

INTEGRATIONS_CORE ?= \
  btrfs \
  disk \
  ssh_check \
  statsd \
  system_core \
  system_swap

BUILD_OPTS ?=

TAG_SUFFIX_LIST := \
	$(shell [ $(ENABLE_PROCESS_AGENT)  -eq 1 ] && echo "-proc") \
	$(shell [ $(ENABLE_SECURITY_AGENT) -eq 1 ] && echo "-sec") \
	$(shell [ $(ENABLE_TRACE_AGENT)    -eq 1 ] && echo "-apm") \
	$(shell [ $(ENABLE_SYSTEM_PROBE)   -eq 1 ] && echo "-sys")

TAG_SUFFIX := $(shell echo $(TAG_SUFFIX_LIST) | sed 's|[ \t]||g; s|-proc-sec-apm-sys|-all|;')-alpine
TAG        := $(DATADOG_MAJOR_VERSION)$(TAG_SUFFIX)

.PHONY: docker-build
docker-build:
	docker build \
		$(BUILD_OPTS) \
		--build-arg ENABLE_PROCESS_AGENT=$(ENABLE_PROCESS_AGENT) \
		--build-arg ENABLE_SECURITY_AGENT=$(ENABLE_SECURITY_AGENT) \
		--build-arg ENABLE_TRACE_AGENT=$(ENABLE_TRACE_AGENT) \
		--build-arg ENABLE_SYSTEM_PROBE=$(ENABLE_SYSTEM_PROBE) \
		--build-arg INTEGRATIONS_CORE="$(INTEGRATIONS_CORE)" \
		-t $(NAME):$(TAG) .
	@echo $(NAME):$(TAG) is built

.PHONY: show-image-tag
show-image-tag:
	@echo "::set-output name=tag::$(NAME):$(TAG)"

.PHONY: show-image-full-tag
show-image-tag:
	@echo "::set-output name=full_tag::$(NAME):$$(docker run --rm --entrypoint /opt/datadog-agent/bin/agent/agent datadog-agent:7-alpine version -n | cut -f2 -d" ")$(TAG_SUFFIX)"
