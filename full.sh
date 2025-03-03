#!/bin/bash

# Create working directory
mkdir -p oncall-setup
cd oncall-setup

# Create docker-compose.yml
cat > docker-compose.yml << 'EOF'
x-environment: &oncall-environment
  DATABASE_TYPE: sqlite3
  BROKER_TYPE: redis
  BASE_URL: $DOMAIN
  SECRET_KEY: $SECRET_KEY
  FEATURE_PROMETHEUS_EXPORTER_ENABLED: ${FEATURE_PROMETHEUS_EXPORTER_ENABLED:-false}
  PROMETHEUS_EXPORTER_SECRET: ${PROMETHEUS_EXPORTER_SECRET:-}
  REDIS_URI: redis://redis:6379/0
  DJANGO_SETTINGS_MODULE: settings.hobby
  CELERY_WORKER_QUEUE: "default,critical,long,slack,telegram,webhook,retry,celery,grafana"
  CELERY_WORKER_CONCURRENCY: "1"
  CELERY_WORKER_MAX_TASKS_PER_CHILD: "100"
  CELERY_WORKER_SHUTDOWN_INTERVAL: "65m"
  CELERY_WORKER_BEAT_ENABLED: "True"
  GRAFANA_API_URL: http://grafana:3000
services:
  engine:
    image: grafana/oncall
    restart: always
    ports:
      - "8080:8080"
    command: sh -c "uwsgi --ini uwsgi.ini"
    environment: *oncall-environment
    volumes:
      - oncall_data:/var/lib/oncall
    depends_on:
      oncall_db_migration:
        condition: service_completed_successfully
      redis:
        condition: service_healthy
    # Modified healthcheck to use Python instead of curl/wget
    healthcheck:
      test: ["CMD", "python3", "-c", "import urllib.request; print(urllib.request.urlopen('http://0.0.0.0:8080/health/').read())"]
      interval: 10s
      timeout: 5s
      retries: 3
      start_period: 30s
  celery:
    image: grafana/oncall
    restart: always
    command: sh -c "./celery_with_exporter.sh"
    environment: *oncall-environment
    volumes:
      - oncall_data:/var/lib/oncall
    depends_on:
      oncall_db_migration:
        condition: service_completed_successfully
      redis:
        condition: service_healthy
  oncall_db_migration:
    image: grafana/oncall
    command: python manage.py migrate --noinput
    environment: *oncall-environment
    volumes:
      - oncall_data:/var/lib/oncall
    depends_on:
      redis:
        condition: service_healthy
  redis:
    image: redis:7.0.15
    restart: always
    expose:
      - 6379
    volumes:
      - redis_data:/data
    deploy:
      resources:
        limits:
          memory: 500m
          cpus: "0.5"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      timeout: 5s
      interval: 5s
      retries: 10
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    container_name: prometheus
    hostname: prometheus
    command:
      - --config.file=/etc/prometheus/prometheus.yml
    ports:
      - 9090:9090
    restart: unless-stopped 
    networks:
      - default
  grafana:
    image: "grafana/${GRAFANA_IMAGE:-grafana:latest}"
    restart: always
    ports:
      - "3000:3000"
    environment:
      GF_FEATURE_TOGGLES_ENABLE: externalServiceAccounts
      GF_SECURITY_ADMIN_USER: ${GRAFANA_USER:-admin}
      GF_SECURITY_ADMIN_PASSWORD: ${GRAFANA_PASSWORD:-admin}
      GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS: grafana-oncall-app
      # GF_INSTALL_PLUGINS: grafana-oncall-app
      GF_INSTALL_PLUGINS: "grafana-oncall-app vv1.9.0"
      GF_AUTH_MANAGED_SERVICE_ACCOUNTS_ENABLED: true
      GRAFANA_CLI_INSECURE_SKIP_VERIFY: true
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana.ini:/etc/grafana/grafana.ini
    deploy:
      resources:
        limits:
          memory: 500m
          cpus: "0.5"
    profiles:
      - with_grafana
  web:
    image: nginx:1.23.1
    ports:
    - "8000:80"
    volumes:
    - ./default.conf:/etc/nginx/conf.d/default.conf
  exporter:
    image: nginx/nginx-prometheus-exporter:0.11
    ports:
      - 9113:9113
    command:
      - -nginx.scrape-uri=http://web:80/metrics
volumes:
  grafana_data:
  prometheus_data:
  oncall_data:
  redis_data:
EOF

# Create prometheus.yml
cat > prometheus.yml << 'EOF'
global:
  scrape_interval: 50s
  evaluation_interval: 60s
  scrape_timeout: 50s
  
scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: [ 'localhost:9090' ]
  - job_name: 'nginx'
    metrics_path: /metrics # Примечание. Если не указать metrics_path, то применится стандартный путь /metrics 
    static_configs:
    - targets: [ 'exporter:9113' ] # Заменили источник метрик на exporter
  - job_name: 'grafana'
    metrics_path: /metrics
    static_configs:
      - targets: [ 'grafana:3000' ]
EOF

# Create default.conf for Nginx
cat > default.conf << 'EOF'
server {
  listen 80;
  listen [::]:80;
  server_name localhost;
  #access_log /var/log/nginx/host.access.log main; 7
  location / {
    root /usr/share/nginx/html;
    index index.html index.htm;
  }
  location /metrics { # Те самые строки кода,
    stub_status on;   # которых нам не хватало
  }
  #error_page 404 /404.html;
  error_page 500 502 503 504 /50x.html;
    location = /50x.html {
    root /usr/share/nginx/html;
  }
}
EOF

# Create empty grafana.ini
touch grafana.ini

# Create .env file
cat > .env << 'EOF'
DOMAIN=http://localhost:8080
COMPOSE_PROFILES=with_grafana
SECRET_KEY=my_random_secret_must_be_more_than_32_characters_long
RABBITMQ_PASSWORD=rabbitmq_secret_pw
MYSQL_PASSWORD=mysql_secret_pw
FEATURE_PROMETHEUS_EXPORTER_ENABLED=false
EOF

# Check if docker-compose is installed
echo "docker-compose not found, installing..."
sudo apt remove docker-compose -y
sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

echo "Setup completed. All necessary files have been created in $(pwd)"
echo "You can now run 'docker-compose up -d' to start the environment"