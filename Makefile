NAME     := datadog-agent

DATADOG_MAJOR_VERSION := 7

ENABLE_PROCESS_AGENT  ?= 1
ENABLE_SECURITY_AGENT ?= 0
ENABLE_TRACE_AGENT    ?= 0
ENABLE_SYSTEM_PROBE   ?= 0

BUILD_OPTS ?=

TAG_SUFFIX_LIST := \
	$(shell [ $(ENABLE_PROCESS_AGENT)  -eq 1 ] && echo "-proc") \
	$(shell [ $(ENABLE_SECURITY_AGENT) -eq 1 ] && echo "-sec") \
	$(shell [ $(ENABLE_TRACE_AGENT)    -eq 1 ] && echo "-apm") \
	$(shell [ $(ENABLE_SYSTEM_PROBE)   -eq 1 ] && echo "-sys")

TAG := $(DATADOG_MAJOR_VERSION)$(shell \
	echo $(TAG_SUFFIX_LIST) | sed 's|[ \t]||g; s|-proc-sec-apm-sys|-all|;')-alpine

.PHONY: docker-build
docker-build:
	docker build \
		$(BUILD_OPTS) \
		--build-arg ENABLE_PROCESS_AGENT=$(ENABLE_PROCESS_AGENT) \
		--build-arg ENABLE_SECURITY_AGENT=$(ENABLE_SECURITY_AGENT) \
		--build-arg ENABLE_TRACE_AGENT=$(ENABLE_TRACE_AGENT) \
		--build-arg ENABLE_SYSTEM_PROBE=$(ENABLE_SYSTEM_PROBE) \
		-t $(NAME):$(TAG) .
	@echo $(NAME):$(TAG) is built

.PHONY: show-image-tag
show-image-tag:
	@echo "::set-output name=tag::$(NAME):$(TAG)"
