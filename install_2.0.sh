#!/bin/bash

set -e

echo "=== Monitoring Installation Script v2.0 ==="

# === Переменные ===
DOCKER_COMPOSE_VERSION=2.35.1
NODE_EXPORTER_VERSION=1.9.0
PROJECT_DIR="/opt/Monitoring"
GF_SECURITY_ADMIN_USER="admin"
GF_SECURITY_ADMIN_PASSWORD="admin"
IP=$(hostname -I | awk '{print $1}')

# === Установка зависимостей ===
sudo apt update -y
sudo apt install -y curl wget apt-transport-https ca-certificates gnupg lsb-release unzip

# === Установка Docker ===
if ! command -v docker &> /dev/null; then
  curl -fsSL https://get.docker.com | sudo bash
else
  echo "Docker уже установлен"
fi

# === Установка Docker Compose ===
if ! command -v docker-compose &> /dev/null; then
  sudo curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
else
  echo "Docker-Compose уже установлен"
fi

# === Установка Node Exporter ===
sudo useradd --no-create-home --shell /usr/sbin/nologin node_exporter || true
cd /tmp
wget https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
tar xvf node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64.tar.gz
sudo cp node_exporter-${NODE_EXPORTER_VERSION}.linux-amd64/node_exporter /usr/local/bin/
sudo chown node_exporter:node_exporter /usr/local/bin/node_exporter

# === systemd unit Node Exporter ===
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

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter

# === Создание каталогов ===
sudo mkdir -p $PROJECT_DIR/{prometheus,grafana/{dashboards,provisioning/{datasources,dashboards}}}
cd $PROJECT_DIR

# === .env файл ===
cat <<EOF | sudo tee $PROJECT_DIR/.env > /dev/null
DOCKER_COMPOSE_VERSION=$DOCKER_COMPOSE_VERSION
NODE_EXPORTER_VERSION=$NODE_EXPORTER_VERSION
PROJECT_DIR=$PROJECT_DIR
GF_SECURITY_ADMIN_USER=$GF_SECURITY_ADMIN_USER
GF_SECURITY_ADMIN_PASSWORD=$GF_SECURITY_ADMIN_PASSWORD
IP=$IP
EOF

# === docker-compose.yml ===
cat <<EOF | sudo tee $PROJECT_DIR/docker-compose.yml > /dev/null
services:
  prometheus:
    image: prom/prometheus
    network_mode: host
    volumes:
      - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./prometheus/alert.rules.yml:/etc/prometheus/alert.rules.yml
    restart: unless-stopped
    healthcheck:
      test: [ "CMD", "wget", "--spider", "-q", "http://localhost:9090/-/healthy" ]
      interval: 10s
      timeout: 5s
      retries: 3
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=3d'
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=${GF_SECURITY_ADMIN_USER}
      - GF_SECURITY_ADMIN_PASSWORD=${GF_SECURITY_ADMIN_PASSWORD}
      - GF_USERS_ALLOW_SIGN_UP=false
      - GF_UPDATE_CHECK=false
      - GF_ANALYTICS_REPORTING_ENABLED=false
    volumes:
      - grafana-storage:/var/lib/grafana
      - ./grafana/provisioning/datasources:/etc/grafana/provisioning/datasources
      - ./grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards
      - ./grafana/dashboards:/etc/grafana/dashboards
    restart: unless-stopped
    healthcheck:
      test: [ "CMD-SHELL", "curl -s http://localhost:3000/api/health | grep -q ok" ]
      interval: 10s
      timeout: 5s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
    networks:
      - monitoring

volumes:
  grafana-storage:

networks:
  monitoring:
EOF

# === prometheus.yml ===
cat <<EOF | sudo tee $PROJECT_DIR/prometheus/prometheus.yml > /dev/null
global:
  scrape_interval: 5s

rule_files:
  - "alert.rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets:
          - localhost:9090

  - job_name: "node-exporter"
    static_configs:
      - targets:
          - localhost:9100
EOF

# === alert.rules.yml ===
cat <<EOF | sudo tee $PROJECT_DIR/prometheus/alert.rules.yml > /dev/null
groups:
  - name: Alerts
    rules:
      - alert: HighCPUUsage
        expr: (1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m]))) * 100 > 80
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage detected (instance {{ \$labels.instance }})"
          description: "CPU usage is above 80% for more than 1 minute."

      - alert: HighMemoryUsage
        expr: (1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage detected (instance {{ \$labels.instance }})"
          description: "Memory usage is above 80% for more than 1 minute."

      - alert: LowDiskSpace
        expr: (node_filesystem_avail_bytes{mountpoint="/",fstype!="tmpfs",fstype!="overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!="tmpfs",fstype!="overlay"}) * 100 < 10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Low disk space on root mount (instance {{ \$labels.instance }})"
          description: "Free space on '/' is below 10%."
EOF

# === dashboards.yml ===
cat <<EOF | sudo tee $PROJECT_DIR/grafana/provisioning/dashboards/dashboards.yml > /dev/null
apiVersion: 1

providers:
  - name: 'default'
    orgId: 1
    folder: ''
    type: file
    disableDeletion: false
    editable: true
    options:
      path: /etc/grafana/dashboards
EOF

# === prometheus datasource ===
cat <<EOF | sudo tee $PROJECT_DIR/grafana/provisioning/datasources/prometheus.yml > /dev/null
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://${IP}:9090
    isDefault: true
    editable: true
EOF

# === Dashboard node_exporter_minimal.json
cat <<EOF | sudo tee $PROJECT_DIR/grafana/dashboards/node_exporter_minimal.json > /dev/null
{
  "annotations": {
    "list": [
      {
        "builtIn": 1,
        "datasource": {
          "type": "grafana",
          "uid": "-- Grafana --"
        },
        "enable": true,
        "hide": true,
        "iconColor": "rgba(0, 211, 255, 1)",
        "name": "Annotations & Alerts",
        "type": "dashboard"
      }
    ]
  },
  "editable": true,
  "fiscalYearStartMonth": 0,
  "graphTooltip": 0,
  "id": 3,
  "links": [],
  "panels": [
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "decimals": 0,
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "orange",
                "value": 70
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 0,
        "y": 0
      },
      "id": 1,
      "options": {
        "minVizHeight": 75,
        "minVizWidth": 75,
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true,
        "sizing": "auto"
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[1m])) by (instance)) * 100",
          "refId": "A"
        }
      ],
      "title": "CPU Usage %",
      "type": "gauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "decimals": 0,
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "orange",
                "value": 70
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 6,
        "y": 0
      },
      "id": 2,
      "options": {
        "minVizHeight": 75,
        "minVizWidth": 75,
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true,
        "sizing": "auto"
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
          "refId": "A"
        }
      ],
      "title": "RAM Usage %",
      "type": "gauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "decimals": 0,
          "mappings": [],
          "max": 100,
          "min": 0,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "orange",
                "value": 70
              },
              {
                "color": "red",
                "value": 90
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 0,
        "y": 4
      },
      "id": 3,
      "options": {
        "minVizHeight": 75,
        "minVizWidth": 75,
        "orientation": "auto",
        "reduceOptions": {
          "calcs": [
            "lastNotNull"
          ],
          "fields": "",
          "values": false
        },
        "showThresholdLabels": false,
        "showThresholdMarkers": true,
        "sizing": "auto"
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(node_filesystem_size_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"} - node_filesystem_free_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"}) / node_filesystem_size_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"} * 100",
          "refId": "A"
        }
      ],
      "title": "Disk Usage %",
      "type": "gauge"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "barWidthFactor": 0.6,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "Bps"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 6,
        "x": 6,
        "y": 4
      },
      "id": 4,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "hideZeros": false,
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "rate(node_network_receive_bytes_total{device=\"eth0\"}[1m])",
          "legendFormat": "In",
          "refId": "A"
        },
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "rate(node_network_transmit_bytes_total{device=\"eth0\"}[1m])",
          "legendFormat": "Out",
          "refId": "B"
        }
      ],
      "title": "Network In/Out (eth0)",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "barWidthFactor": 0.6,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "decimals": 0,
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 12,
        "x": 0,
        "y": 8
      },
      "id": 5,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "hideZeros": false,
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(1 - avg(rate(node_cpu_seconds_total{mode=\"idle\"}[1m])) by (instance)) * 100",
          "refId": "A"
        }
      ],
      "title": "CPU Usage Over Time",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "barWidthFactor": 0.6,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "decimals": 0,
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 12,
        "x": 0,
        "y": 12
      },
      "id": 6,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "hideZeros": false,
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100",
          "refId": "A"
        }
      ],
      "title": "RAM Usage Over Time",
      "type": "timeseries"
    },
    {
      "datasource": {
        "type": "prometheus",
        "uid": "PBFA97CFB590B2093"
      },
      "fieldConfig": {
        "defaults": {
          "color": {
            "mode": "palette-classic"
          },
          "custom": {
            "axisBorderShow": false,
            "axisCenteredZero": false,
            "axisColorMode": "text",
            "axisLabel": "",
            "axisPlacement": "auto",
            "barAlignment": 0,
            "barWidthFactor": 0.6,
            "drawStyle": "line",
            "fillOpacity": 0,
            "gradientMode": "none",
            "hideFrom": {
              "legend": false,
              "tooltip": false,
              "viz": false
            },
            "insertNulls": false,
            "lineInterpolation": "linear",
            "lineWidth": 1,
            "pointSize": 5,
            "scaleDistribution": {
              "type": "linear"
            },
            "showPoints": "auto",
            "spanNulls": false,
            "stacking": {
              "group": "A",
              "mode": "none"
            },
            "thresholdsStyle": {
              "mode": "off"
            }
          },
          "decimals": 0,
          "mappings": [],
          "thresholds": {
            "mode": "absolute",
            "steps": [
              {
                "color": "green"
              },
              {
                "color": "red",
                "value": 80
              }
            ]
          },
          "unit": "percent"
        },
        "overrides": []
      },
      "gridPos": {
        "h": 4,
        "w": 12,
        "x": 0,
        "y": 16
      },
      "id": 7,
      "options": {
        "legend": {
          "calcs": [],
          "displayMode": "list",
          "placement": "bottom",
          "showLegend": true
        },
        "tooltip": {
          "hideZeros": false,
          "mode": "single",
          "sort": "none"
        }
      },
      "pluginVersion": "11.6.1",
      "targets": [
        {
          "datasource": {
            "type": "prometheus",
            "uid": "PBFA97CFB590B2093"
          },
          "expr": "(node_filesystem_size_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"} - node_filesystem_free_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"}) / node_filesystem_size_bytes{fstype!=\"tmpfs\",mountpoint=\"/\"} * 100",
          "refId": "A"
        }
      ],
      "title": "Disk Usage Over Time",
      "type": "timeseries"
    }
  ],
  "preload": false,
  "refresh": "5s",
  "schemaVersion": 41,
  "tags": [],
  "templating": {
    "list": []
  },
  "time": {
    "from": "now-1h",
    "to": "now"
  },
  "timepicker": {},
  "timezone": "browser",
  "title": "Node Exporter Minimal",
  "uid": "bel39dy5jzyf4c",
  "version": 6
}
EOF

# === systemd unit monitoring.service ===
sudo tee /etc/systemd/system/monitoring.service > /dev/null <<EOF
[Unit]
Description=Prometheus + Grafana Monitoring Stack
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/Monitoring
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
EOF

# === Запуск docker-compose (Prometheus + Grafana)
cd $PROJECT_DIR
sudo docker-compose up -d

# === Финальный запуск ===
sudo systemctl daemon-reload
sudo systemctl enable monitoring
sudo systemctl start monitoring

echo "✅ Установка завершена."
echo "🔗 Grafana: http://localhost:3000 (user: $GF_SECURITY_ADMIN_USER / pass: $GF_SECURITY_ADMIN_PASSWORD)"
echo "🔗 Prometheus: http://localhost:9090"
