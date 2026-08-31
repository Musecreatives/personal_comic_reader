FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

# /data is where sync.db lives - bind-mount this from the host's root
# disk (NOT /mnt/media-pool - see main.py's module docstring for why).
VOLUME ["/data"]
ENV SYNC_DB_PATH=/data/sync.db

EXPOSE 8600

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8600"]
