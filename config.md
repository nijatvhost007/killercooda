echo "DOMAIN=http://localhost:8080
COMPOSE_PROFILES=with_grafana
SECRET_KEY=my_random_secret_must_be_more_than_32_characters_long
RABBITMQ_PASSWORD=rabbitmq_secret_pw
MYSQL_PASSWORD=mysql_secret_pw
FEATURE_PROMETHEUS_EXPORTER_ENABLED=false" > .env

sudo apt remove docker-compose -y

sudo curl -L "https://github.com/docker/compose/releases/download/v2.23.0/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose
sudo rm /usr/bin/docker-compose
sudo ln -s /usr/local/bin/docker-compose /usr/bin/docker-compose
