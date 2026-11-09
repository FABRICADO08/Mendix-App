# --- Stage 1: The Build Environment ---
FROM python:3.11-slim-bookworm AS builder

# Install Java (Required for Mendix Runtime) and Unzip
RUN mkdir -p /usr/share/man/man1 && \
    apt-get update && apt-get install -y \
    openjdk-17-jdk-headless \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set up Mendix paths
WORKDIR /opt/mendix/app

# 1. Pull the Mendix Runtime
# We use the version you defined in your env
ARG MENDIX_VERSION=10.24.1.74050
RUN curl -fsSL https://cdn.mendix.com/runtime/mendix-${MENDIX_VERSION}.tar.gz | tar -xz -C /opt/mendix/app

# 2. Copy and Extract your MDA
COPY deployment/app.mda /tmp/app.mda
RUN unzip -q /tmp/app.mda -d /opt/mendix/app

# 3. Install m2ee (This is what actually starts Mendix, replaces the missing 'mx')
RUN pip install --no-cache-dir m2ee-tools

# --- Stage 2: The Runtime Image ---
FROM python:3.11-slim-bookworm

# Copy Java and Mendix from the builder
COPY --from=builder /usr/local /usr/local
COPY --from=builder /usr/lib/jvm /usr/lib/jvm
COPY --from=builder /opt/mendix /opt/mendix

# Set environment for Java
ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
ENV PATH="$JAVA_HOME/bin:$PATH"

WORKDIR /opt/mendix/app

# Create a simple startup script since 'bin/mx' doesn't exist
RUN echo '#!/bin/bash\nm2ee -c /opt/mendix/app/m2ee.yaml start' > /opt/mendix/app/start.sh && \
    chmod +x /opt/mendix/app/start.sh
    

# Mendix standard port
EXPOSE 8080

CMD ["/opt/mendix/app/start.sh"]
