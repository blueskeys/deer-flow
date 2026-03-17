FROM python:3.12-slim

# Set to "cn" to use China mirrors, empty for official sources
ARG MIRROR_REGION=

# Configure China mirrors for faster builds in China
RUN if [ "$MIRROR_REGION" = "cn" ]; then \
    sed -i 's/deb.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources \
    && sed -i 's/security.debian.org/mirrors.aliyun.com/g' /etc/apt/sources.list.d/debian.sources; \
    fi

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (use Tsinghua mirror for China)
RUN if [ "$MIRROR_REGION" = "cn" ]; then \
    pip config set global.index-url https://pypi.tuna.tsinghua.edu.cn/simple; \
    fi \
    && pip install --no-cache-dir \
    fastapi \
    "uvicorn[standard]" \
    kubernetes

WORKDIR /app
COPY app.py .

EXPOSE 8002

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8002"]
