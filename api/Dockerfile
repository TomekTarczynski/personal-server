FROM python:3.12-slim

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash curl ca-certificates sqlite3 tar gzip \
 && rm -rf /var/lib/apt/lists/*

COPY api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY api/main.py .
COPY api/scripts/ /opt/scripts/
RUN chmod +x /opt/scripts/*.sh

ENV PORT=8000
EXPOSE 8000

CMD ["python", "main.py"]