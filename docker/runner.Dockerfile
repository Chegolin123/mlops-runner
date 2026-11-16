# syntax=docker/dockerfile:1
# Runner в контейнере: альтернатива systemd-установке.
FROM ubuntu:22.04

ARG RUNNER_VERSION=2.319.1
ARG TARGETARCH=amd64

ENV DEBIAN_FRONTEND=noninteractive \
    RUNNER_ALLOW_RUNASROOT=0

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl git jq sudo python3 python3-venv python3-pip tini \
 && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/runner runner \
 && mkdir -p /actions-runner && cd /actions-runner \
 && curl -fsSL -o runner.tar.gz \
      "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" \
 && tar xzf runner.tar.gz && rm runner.tar.gz \
 && ./bin/installdependencies.sh \
 && chown -R runner:runner /actions-runner

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER runner
WORKDIR /actions-runner
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]
