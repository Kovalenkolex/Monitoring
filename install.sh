#!/bin/bash

set -e
source ./.env

echo "[+] Обновляем систему и устанавливаем зависимости..."
sudo apt update -y
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release

echo "[+] Установка Docker..."
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo bash
else
  echo "[✓] Docker уже установлен"
fi

echo "[+] Установка Docker Compose версии ${DOCKER_COMPOSE_VERSION}..."
if ! command -v docker-compose &> /dev/null; then
  sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
  -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
else
  echo "[✓] Docker Compose уже установлен"
fi

echo "[+] Создание пользователя 'node_exporter'..."
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true

echo "[+] Загрузка и установка Node Exporter..."
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvf node_exporter-$NODE_EXPORTER_VERSION.linux-amd64.tar.gz
sudo cp node_exporter-$NODE_EXPORTER_VERSION.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

echo "[+] Создание systemd unit-файла для Node Exporter..."
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

echo "[+] Перезапуск и включение Node Exporter..."
sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

echo "[✓] Установка завершена успешно!"
