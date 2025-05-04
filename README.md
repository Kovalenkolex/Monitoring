# Monitoring
Bash script that installs and sets up Monitoring tools (Node Exporter, Prometheus, Grafana)
## Technology stack  
<p align="left">
  <a href="https://www.linux.org" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/linux-colored.svg" width="36" height="36" alt="Linux" /></a>
  <a href="https://www.gnu.org/software/bash/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/gnubash.svg" width="36" height="36" alt="GNU Bash" /></a>
  <a href="https://www.docker.com/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/danielcranney/readme-generator/main/public/icons/skills/docker-colored.svg" width="36" height="36" alt="Docker" /></a>
  <a href="https://grafana.com/" target="_blank" rel="noreferrer"><img src="https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg" width="36" height="36" alt="Grafana" /></a>
  <a href="https://prometheus.io/" target="_blank" rel="noreferrer"><img src="https://upload.wikimedia.org/wikipedia/commons/3/38/Prometheus_software_logo.svg" width="36" height="36" alt="Prometheus" /></a>
</p>

\
Bash script:
1) Installs Docker, Docker-Compose and Node exporter on Server
2) Runs Docker-Compose file with Prometheus and Grafana
3) Creates prometheus.conf with scrape job
4) Creates Dashboard (CPU, RAM, disk I/O)
5) 