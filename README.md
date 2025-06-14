# Monitoring
Bash script that installs and sets up Monitoring tools (Node Exporter, Prometheus, Grafana)

### Prometheus:
http://YOUR_IP:9090  
### Grafana:
http://YOUR_IP:3000

## Technology stack  
<p align="left">
  <a href="https://www.linux.org" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/linux-colored.svg" width="36" height="36" alt="Linux" /></a>
  <a href="https://www.gnu.org/software/bash/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/gnubash.svg" width="36" height="36" alt="GNU Bash" /></a>
  <a href="https://www.docker.com/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/docker-colored.svg" width="36" height="36" alt="Docker" /></a>
  <a href="https://grafana.com/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg" width="36" height="36" alt="Grafana" /></a>
  <a href="https://prometheus.io/" target="_blank" rel="noreferrer"><img src="https://upload.wikimedia.org/wikipedia/commons/3/38/Prometheus_software_logo.svg" width="36" height="36" alt="Prometheus" /></a>
</p>

## Architecture

```mermaid
graph TD
    A[Node Exporter<br>] -->| Scraped by | B[(Prometheus<br>)]
    B -->| Queried by | C[Grafana<br>]

    subgraph Server
        A
    end

    subgraph Docker Compose Stack
        B
        C
    end
```

## How to run

```bash
cd /opt
git clone https://github.com/Kovalenkolex/Monitoring.git
cd Monitoring
sudo chmod +x install.sh
sudo ./install.sh
cd /opt/Monitoring
docker-compose up -d
```

## How to run 2.0 (no git)
```bash
cd /opt
sudo nano install_2.0.sh
*copy the file install_2.0.sh*
sudo chmod +x install_2.0.sh
sudo ./install_2.0.sh
```

Bash script:
1) Installs Docker, Docker-Compose and Node exporter on Server
2) Runs Docker-Compose file with Prometheus and Grafana
3) Creates prometheus.conf with scrape job
4) Creates Dashboard (CPU, RAM, disk I/O, NET)
5) Creates alerts for high load CPU, RAM, low disk space
6) Creates systemd unit for monitoring system



## Alerts (PromQL)

- **High CPU usage**  
Triggers when average CPU usage is above 80% for 1 minute:
```
(1 - avg(rate(node_cpu_seconds_total{mode="idle"}[1m]))) * 100 > 80
```
- **High RAM usage**
Triggers when available RAM usage is above 80%:
```
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100 > 80
```
- **Low disk space**
Triggers when available disk space on root filesystem is lower than 10%:
```
(node_filesystem_avail_bytes{fstype!="overlay",fstype!="tmpfs",mountpoint="/"} / node_filesystem_size_bytes{fstype!="overlay",fstype!="tmpfs",mountpoint="/"}) * 100 < 10
```

## Dashboard Example
![Grafana Dashboard Screenshot](./docs/dashboard.png)
## Alerts Example
![Prometheus Alerts Screenshot](./docs/alerts.png)
