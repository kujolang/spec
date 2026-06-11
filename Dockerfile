# Spec Docker Image
# Build: docker build -t kujolang/spec:latest .
# Run:   docker run --rm -v $(pwd):/workspace -w /workspace kujolang/spec validate spec.yml
#        docker run --rm kujolang/spec version

FROM python:3.11-alpine

LABEL org.opencontainers.image.title="Spec"
LABEL org.opencontainers.image.description="Structured task definition format for AI-native development"
LABEL org.opencontainers.image.url="https://github.com/kujolang/spec"
LABEL org.opencontainers.image.source="https://github.com/kujolang/spec"
LABEL org.opencontainers.image.licenses="MIT"

# Install system deps
RUN apk add --no-cache bash git

# Install Python deps for YAML/TOML support
RUN pip install --no-cache-dir pyyaml

# Copy Kujo runtime binary (must be provided at build time)
# Build with: docker build --build-arg KUJO_BIN_URL=<url> -t kujolang/spec .
ARG KUJO_BIN_URL=""
ARG KUJO_BIN_PATH="/usr/local/bin/kujo"

RUN if [ -n "$KUJO_BIN_URL" ]; then \
		wget -O "$KUJO_BIN_PATH" "$KUJO_BIN_URL" && \
		chmod +x "$KUJO_BIN_PATH"; \
	else \
		echo "Warning: KUJO_BIN_URL not set. Kujo runtime must be mounted at runtime."; \
		touch "$KUJO_BIN_PATH"; \
	fi

ENV KUJO_BIN=/usr/local/bin/kujo

# Copy spec tool
COPY scripts/ /opt/kujo-spec/scripts/
COPY src/ /opt/kujo-spec/src/
COPY schema/ /opt/kujo-spec/schema/
COPY kennel.toml /opt/kujo-spec/

# Create entrypoint wrapper
RUN printf '#!/bin/bash\n\
export KUJO_BIN="${KUJO_BIN:-/usr/local/bin/kujo}"\n\
cd /opt/kujo-spec\n\
exec bash /opt/kujo-spec/scripts/spec "$@"\n' > /usr/local/bin/spec && \
	chmod +x /usr/local/bin/spec

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/spec"]
CMD ["help"]
