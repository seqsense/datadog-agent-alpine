# datadog-agent-alpine
Small footprint datadog-agent  based on Alpine Linux

## Getting started
Availability of `process-agent`, `security-agent`, `trace-agent`, and `system-probe` can be switched by the make arguments: `ENABLE_PROCESS_AGENT`, `ENABLE_SECURITY_AGENT`, `ENABLE_TRACE_AGENT`, `ENABLE_SYSTEM_PROBE` (set `1` to enable)
`process-agent` is enabled by default.

Installed integrations can be selected by `INTEGRATIONS_CORE` argument.
`btrfs`, `disk`, `ssh_check`, `statsd`, `system_core`, `system_swap` are enabled by default.

For example, following command will build the Alpine based image with `process-agent` and `trace-agent`.
```shell
make docker-build ENABLE_TRACE_AGENT=1
```

## Run
The image works basically same as the official datadog-agent image.
For some reason, this image requires `seccomp` or `apparmor` setting to use `journald` integration.
```yaml
# docker-compose.yml
    security_opt:
      - "apparmor:unconfined"
      - "seccomp:unconfined"
```
```shell
docker run --security-opt=seccomp=unconfined --security-opt=apparmor=unconfined ...
```

## Docker images

Pre-built images with some combination of the features are available on GitHub Container Registry.

```shell
# Image including process-agent
docker pull ghcr.io/seqsense/datadog-agent:7-proc-alpine

# Image including process-agent and trace-agent
docker pull ghcr.io/seqsense/datadog-agent:7-proc-apm-alpine

# Image including process-agent, security-agent, trace-agent, and system-probe
docker pull ghcr.io/seqsense/datadog-agent:7-all-alpine
```

## License
The scripts to build the images are licensed under the [Apache License, Version 2.0](LICENSE).

The Datadog agent user space components are licensed under the [Apache License, Version 2.0](https://github.com/DataDog/datadog-agent/blob/master/LICENSE).
The BPF code is licensed under the [General Public License, Version 2.0](https://github.com/DataDog/datadog-agent/blob/master/pkg/ebpf/c/COPYING).
See https://github.com/DataDog/datadog-agent/#license for the details.
