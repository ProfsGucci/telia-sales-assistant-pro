FROM python:3.12-slim

WORKDIR /app
COPY server.py .

ENV PORT=8080
EXPOSE 8080

# UPSTREAM_URL, UPSTREAM_KEY (required), PROXY_TOKEN and MODEL_OVERRIDE
# are provided at runtime — never baked into the image.
CMD ["python3", "server.py"]
