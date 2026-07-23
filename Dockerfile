FROM python:3.11-alpine
RUN apk update && \
    apk upgrade --no-cache && \
    apk add --no-cache curl
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "main.py"]