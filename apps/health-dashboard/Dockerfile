FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

# Use fixed numeric IDs so Kubernetes can verify runAsNonRoot.
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin app \
    && chown -R 10001:10001 /app

USER 10001:10001

EXPOSE 8080

ENV FLASK_APP=app.py \
    FLASK_RUN_HOST=0.0.0.0 \
    FLASK_RUN_PORT=8080 \
    PYTHONUNBUFFERED=1

CMD ["gunicorn", "--workers", "2", "--threads", "2", "--timeout", "60", "--bind", "0.0.0.0:8080", "app:app"]
