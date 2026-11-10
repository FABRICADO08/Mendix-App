# ------------------------------------------------------------
# Stage 1: Mendix build environment
# ------------------------------------------------------------
FROM eclipse-temurin:21-jdk-jammy AS builder

ARG MENDIX_VERSION=11.16.0
ARG M2EE_VERSION=8.0.1

RUN mkdir -p /usr/share/man/man1 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/mendix/app

# Download the matching Mendix Runtime
RUN mkdir -p /opt/mendix/app/runtimes && \
    curl -fsSL \
        "https://cdn.mendix.com/runtime/mendix-${MENDIX_VERSION}.tar.gz" | \
    tar -xz -C /opt/mendix/app/runtimes

# build-mda.yml must create this file before the Docker build starts
COPY deployment/app.mda /tmp/app.mda

# Extract the compiled Mendix application
RUN unzip -q /tmp/app.mda -d /opt/mendix/app && \
    rm -f /tmp/app.mda

# Download the m2ee command-line script
RUN curl -fsSL \
        "https://raw.githubusercontent.com/mendix/m2ee-tools/v${M2EE_VERSION}/src/m2ee.py" \
        -o /tmp/m2ee-cli.py && \
    sed -i \
        '/^if not sys.stdout.isatty():/,/^        sys.stdout = codecs.getwriter(locale.getpreferredencoding())(sys.stdout)$/d' \
        /tmp/m2ee-cli.py


# ------------------------------------------------------------
# Stage 2: Mendix runtime image
# ------------------------------------------------------------
FROM python:3.11-slim-bookworm

ARG M2EE_VERSION=8.0.1

ENV JAVA_HOME=/opt/java/openjdk
ENV PATH="/opt/java/openjdk/bin:${PATH}"
ENV PYTHONUNBUFFERED=1

WORKDIR /opt/mendix/app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl && \
    rm -rf /var/lib/apt/lists/*

# Copy Java, Mendix Runtime, application files and m2ee
COPY --from=builder /opt/java/openjdk /opt/java/openjdk
COPY --from=builder /opt/mendix /opt/mendix
COPY --from=builder /tmp/m2ee-cli.py /usr/local/bin/m2ee-cli.py

RUN pip install --no-cache-dir \
        PyYAML \
        requests \
        "https://github.com/mendix/m2ee-tools/archive/refs/tags/v${M2EE_VERSION}.tar.gz" && \
    printf '%s\n' \
        '#!/bin/sh' \
        'exec python3 /usr/local/bin/m2ee-cli.py "$@"' \
        > /usr/local/bin/m2ee && \
    chmod +x \
        /usr/local/bin/m2ee \
        /usr/local/bin/m2ee-cli.py && \
    mkdir -p \
        /opt/mendix/app/data/tmp \
        /opt/mendix/app/data/log

# Create the container startup script
RUN cat > /opt/mendix/app/start.sh <<'EOF'
#!/bin/sh
set -eu

echo "Starting Mendix container..."

if [ -z "${DATABASE_URL:-}" ]; then
    echo "ERROR: DATABASE_URL is not configured."
    exit 1
fi

if [ -z "${MENDIX_ADMIN_PASSWORD:-}" ]; then
    echo "ERROR: MENDIX_ADMIN_PASSWORD is not configured."
    exit 1
fi

# Azure normally routes to the port configured by WEBSITES_PORT.
# The Mendix runtime listens on PORT when provided, otherwise 10000.
export MENDIX_RUNTIME_PORT="${PORT:-10000}"

python3 - <<'PY'
import os
import sys
from urllib.parse import parse_qsl, unquote, urlencode, urlparse

database_url = os.environ["DATABASE_URL"].strip()
parsed = urlparse(database_url)

if parsed.scheme not in ("postgres", "postgresql"):
    print(
        "ERROR: DATABASE_URL must begin with postgres:// or postgresql://",
        file=sys.stderr,
    )
    sys.exit(1)

if not parsed.hostname:
    print("ERROR: DATABASE_URL has no hostname.", file=sys.stderr)
    sys.exit(1)

if not parsed.username:
    print("ERROR: DATABASE_URL has no username.", file=sys.stderr)
    sys.exit(1)

if parsed.password is None:
    print("ERROR: DATABASE_URL has no password.", file=sys.stderr)
    sys.exit(1)

host = parsed.hostname
port = parsed.port or 5432
database = unquote(parsed.path.lstrip("/")) or "postgres"
username = unquote(parsed.username)
password = unquote(parsed.password)

runtime_port_value = os.environ.get("MENDIX_RUNTIME_PORT", "10000")

try:
    runtime_port = int(runtime_port_value)
except ValueError:
    print(
        f"ERROR: Invalid runtime port: {runtime_port_value}",
        file=sys.stderr,
    )
    sys.exit(1)

if not 1 <= runtime_port <= 65535:
    print(
        f"ERROR: Runtime port outside valid range: {runtime_port}",
        file=sys.stderr,
    )
    sys.exit(1)

query = dict(parse_qsl(parsed.query, keep_blank_values=True))

# Neon requires an encrypted PostgreSQL connection.
query.setdefault("sslmode", "require")

# Remove the psql-specific parameter before building the JDBC URL.
query.pop("channel_binding", None)

jdbc_url = (
    f"jdbc:postgresql://{host}:{port}/{database}"
    f"?{urlencode(query)}"
)


def yaml_string(value):
    return "'" + str(value).replace("'", "''") + "'"


config_path = "/opt/mendix/app/m2ee.yaml"

configuration = [
    "m2ee:",
    "  app_name: App",
    "  app_base: /opt/mendix/app",
    "  admin_port: 8090",
    (
        "  admin_pass: "
        + yaml_string(os.environ["MENDIX_ADMIN_PASSWORD"])
    ),
    f"  runtime_port: {runtime_port}",
    '  runtime_listen_addresses: "*"',
    (
        '  javaopts: ["-Dfile.encoding=UTF-8", '
        '"-Djava.io.tmpdir=/opt/mendix/app/data/tmp"]'
    ),
    "  logfile: /opt/mendix/app/data/log/runtime.log",
    "",
    "logging:",
    "  - name: ConsoleSubscriber",
    "    type: console",
    "    autosubscribe: INFO",
    "",
    "mxruntime:",
    "  DatabaseType: PostgreSQL",
    f"  DatabaseJdbcUrl: {yaml_string(jdbc_url)}",
    f"  DatabaseUserName: {yaml_string(username)}",
    f"  DatabasePassword: {yaml_string(password)}",
    "  ScheduledEventExecution: NONE",
    "",
]

with open(config_path, "w", encoding="utf-8") as config:
    config.write("\n".join(configuration))

print(f"Generated Mendix configuration at {config_path}")
print(f"Mendix runtime port: {runtime_port}")
print(f"Database host: {host}")
print(f"Database name: {database}")
PY

mkdir -p /opt/mendix/app/data/tmp
mkdir -p /opt/mendix/app/data/log
touch /opt/mendix/app/data/log/runtime.log

echo "Starting Mendix Runtime..."

if m2ee -c /opt/mendix/app/m2ee.yaml start; then
    echo "Mendix startup command completed."
else
    status=$?

    echo "ERROR: Mendix failed to start. Exit code: ${status}"
    echo "========== Mendix runtime log =========="

    if [ -f /opt/mendix/app/data/log/runtime.log ]; then
        cat /opt/mendix/app/data/log/runtime.log
    else
        echo "No runtime log was created."
    fi

    echo "========================================"
    exit "$status"
fi

exec tail -n +1 -F /opt/mendix/app/data/log/runtime.log
EOF

RUN chmod +x /opt/mendix/app/start.sh

EXPOSE 10000

CMD ["/opt/mendix/app/start.sh"]
