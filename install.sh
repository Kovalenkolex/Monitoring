#!/bin/bash

set -e
source ./.env

# Обновляем систему и устанавливаем зависимости
sudo apt update -y
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

# Установка Docker
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo bash
else
  echo "Docker уже установлен"
fi

# Установка Docker Compose версии из .env
if ! command -v docker-compose &> /dev/null; then
  sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
else
  echo "Docker-Compose уже установлен"
fi

# Создание пользователя 'node_exporter'
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true

# Загрузка и установка Node Exporter
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
sudo cp node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

#Создание systemd unit-файла для Node Exporter
sudo tee /etc/systemd/system/node_exporter.service > /dev/null <<EOF
[Unit]
Description=Node Exporter
Wants=network-online.target
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

[Install]
WantedBy=default.target
EOF

# Перезапуск и запуск Node Exporter
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# Создание systemd unit-файла для docker-compose мониторинга
sudo tee /etc/systemd/system/monitoring.service > /dev/null <<EOF
[Unit]
Description=Prometheus + Grafana Monitoring Stack
Requires=docker.service
After=docker.service

[Service]
WorkingDirectory=$PROJECT_DIR
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
Restart=always
TimeoutStartSec=0

[Install]
WantedBy=multi-user.target
EOF

# Запуск systemd юнита
sudo systemctl daemon-reload
sudo systemctl enable monitoring
sudo systemctl start monitoring

echo "Установка завершена успешно"
