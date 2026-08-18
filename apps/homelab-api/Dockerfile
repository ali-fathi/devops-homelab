FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Use a fixed numeric identity so the image remains non-root when deployed
# with Kubernetes runAsNonRoot security controls.
RUN groupadd --gid 10001 app \
    && useradd --uid 10001 --gid 10001 --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin app

COPY --chown=10001:10001 app.py .

USER 10001:10001

EXPOSE 8080

ENV PYTHONDONTWRITEBYTECODE=1

CMD ["python", "app.py"]
