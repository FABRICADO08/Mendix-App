# --- Stage 1: The Build Environment ---
FROM eclipse-temurin:21-jdk-jammy AS builder

RUN mkdir -p /usr/share/man/man1 && \
    apt-get update && apt-get install -y \
    unzip \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mendix/app

ARG MENDIX_VERSION=11.16.0
RUN curl -fsSL "https://cdn.mendix.com/runtime/mendix-${MENDIX_VERSION}.tar.gz" | \
    tar -xz -C /opt/mendix/app

COPY deployment/app.mda /tmp/app.mda
RUN unzip -q /tmp/app.mda -d /opt/mendix/app

# Keep the m2ee CLI source available for the runtime image. The package's
# setup.py installs the library but does not register the CLI as an executable.
RUN curl -fsSL \
    "https://raw.githubusercontent.com/mendix/m2ee-tools/v8.0.1/src/m2ee.py" \
    -o /tmp/m2ee

# --- Stage 2: The Runtime Image ---
FROM python:3.11-slim-bookworm

COPY --from=builder /usr/local /usr/local
COPY --from=builder /opt/java/openjdk /opt/java/openjdk
COPY --from=builder /opt/mendix /opt/mendix
COPY --from=builder /tmp/m2ee /usr/local/bin/m2ee.py

# Set environment for Java
ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="$JAVA_HOME/bin:$PATH"

WORKDIR /opt/mendix/app

RUN pip install --no-cache-dir \
        PyYAML \
        https://github.com/mendix/m2ee-tools/archive/refs/tags/v8.0.1.tar.gz && \
    printf '%s\n' '#!/bin/sh' 'exec python3 /usr/local/bin/m2ee.py "$@"' \
        > /usr/local/bin/m2ee && \
    chmod +x /usr/local/bin/m2ee /usr/local/bin/m2ee.py && \
    mkdir -p /opt/mendix/app/data/tmp /opt/mendix/app/data/log && \
    cat > /opt/mendix/app/start.sh <<'EOF'
#!/bin/sh
set -eu

: "${DATABASE_URL:?DATABASE_URL must be configured with the Neon PostgreSQL connection string}"
: "${MENDIX_ADMIN_PASSWORD:?MENDIX_ADMIN_PASSWORD must be configured}"

python3 - <<'PY'
import os
from urllib.parse import unquote, urlparse

database_url = os.environ["DATABASE_URL"]
parsed = urlparse(database_url)

if parsed.scheme not in ("postgres", "postgresql"):
    raise SystemExit("DATABASE_URL must use the postgres:// or postgresql:// scheme")
if not parsed.hostname or not parsed.username or parsed.password is None:
    raise SystemExit("DATABASE_URL must include a host, username, and password")

def yaml_string(value):
    return "'" + str(value).replace("'", "''") + "'"

runtime_port = os.environ.get("PORT", "8080")
database_host = parsed.hostname
if parsed.port:
    database_host = f"{database_host}:{parsed.port}"
database_name = unquote(parsed.path.lstrip("/")) or "postgres"

with open("/opt/mendix/app/m2ee.yaml", "w", encoding="utf-8") as config:
    config.write(
        "\n".join(
            [
                "m2ee:",
                "  app_name: App",
                "  app_base: /opt/mendix/app",
                "  admin_port: 8090",
                f"  admin_pass: {yaml_string(os.environ['MENDIX_ADMIN_PASSWORD'])}",
                f"  runtime_port: {runtime_port}",
                '  runtime_listen_addresses: "*"',
                '  javaopts: ["-Dfile.encoding=UTF-8", "-Djava.io.tmpdir=/opt/mendix/app/data/tmp"]',
                "  logfile: /opt/mendix/app/data/log/runtime.log",
                "logging:",
                "  - name: FileSubscriber",
                "    type: file",
                "    autosubscribe: INFO",
                "    filename: /opt/mendix/app/data/log/runtime.log",
                "mxruntime:",
                "  DatabaseType: PostgreSQL",
                f"  DatabaseHost: {yaml_string(database_host)}",
                f"  DatabaseName: {yaml_string(database_name)}",
                f"  DatabaseUserName: {yaml_string(unquote(parsed.username))}",
                f"  DatabasePassword: {yaml_string(unquote(parsed.password))}",
                "  DatabaseUseSsl: true",
                "  ScheduledEventExecution: NONE",
                "",
            ]
        )
    )
PY

exec m2ee -c /opt/mendix/app/m2ee.yaml start
EOF
RUN chmod +x /opt/mendix/app/start.sh

EXPOSE 8080

CMD ["/opt/mendix/app/start.sh"]
