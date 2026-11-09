# --- Stage 1: The Build Environment ---
FROM python:3.11-slim-bookworm AS builder

RUN mkdir -p /usr/share/man/man1 && \
    apt-get update && apt-get install -y \
    openjdk-17-jdk-headless \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mendix/app

ARG MENDIX_VERSION=11.16.0
RUN curl -fsSL "https://cdn.mendix.com/runtime/mendix-${MENDIX_VERSION}.tar.gz" | \
    tar -xz -C /opt/mendix/app

COPY deployment/app.mda /tmp/app.mda
RUN unzip -q /tmp/app.mda -d /opt/mendix/app

# 3. Install m2ee tools (PyPI package is unavailable; install from official GitHub tag)
RUN pip install --no-cache-dir https://github.com/mendix/m2ee-tools/archive/refs/tags/v8.0.1.tar.gz

# --- Stage 2: The Runtime Image ---
FROM python:3.11-slim-bookworm

COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/lib/jvm /usr/lib/jvm
COPY --from=builder /opt/mendix /opt/mendix

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

WORKDIR /opt/mendix/app

RUN mkdir -p /opt/mendix/app/data/tmp /opt/mendix/app/data/log && \
    printf '%s\n' \
    'm2ee:' \
    '  app_name: App' \
    '  app_base: /opt/mendix/app' \
    '  admin_port: 8090' \
    '  admin_pass: change-me' \
    '  runtime_port: 8080' \
    '  runtime_listen_addresses: "*"' \
    '  javaopts: ["-Dfile.encoding=UTF-8", "-Djava.io.tmpdir=/opt/mendix/app/data/tmp"]' \
    '  logfile: /opt/mendix/app/data/log/runtime.log' \
    'logging:' \
    '  - name: FileSubscriber' \
    '    type: file' \
    '    autosubscribe: INFO' \
    '    filename: /opt/mendix/app/data/log/runtime.log' \
    'mxruntime:' \
    '  DatabaseType: PostgreSQL' \
    '  DatabaseHost: "127.0.0.1:5432"' \
    '  DatabaseName: app' \
    '  DatabaseUserName: app' \
    '  DatabasePassword: app' \
    '  ScheduledEventExecution: NONE' \
    > /opt/mendix/app/m2ee.yaml

RUN printf '%s\n' \
    '#!/bin/sh' \
    'set -eu' \
    'exec m2ee -c /opt/mendix/app/m2ee.yaml start' \
    > /opt/mendix/app/start.sh && \
    chmod +x /opt/mendix/app/start.sh

EXPOSE 8080

CMD ["/opt/mendix/app/start.sh"]
