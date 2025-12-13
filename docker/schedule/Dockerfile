FROM docker:latest

WORKDIR /app

RUN apk add --no-cache python3 py3-yaml py3-pip && \
    pip3 install --no-cache-dir --break-system-packages croniter

COPY scheduler.py .

ENTRYPOINT ["python3", "scheduler.py"]