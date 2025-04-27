FROM python:3.12-slim

# Set timezone
ENV TZ=America/New_York
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install -r requirements.txt gunicorn

COPY serve_config.py .

# Create the config_files directory inside the image
RUN mkdir -p /app/config_files

# Copy JSON files from the 'config_files' subdir in the build context
# into the '/app/config_files/' directory inside the image
COPY config_files/*.json /app/config_files/

EXPOSE 5000

CMD ["gunicorn", "--workers", "4", "--bind", "0.0.0.0:5000", "--log-level", "info", "serve_config:app"]