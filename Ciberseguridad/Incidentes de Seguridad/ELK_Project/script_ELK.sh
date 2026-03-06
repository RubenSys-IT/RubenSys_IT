#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# VALIDACIONES
# -------------------------------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] Ejecuta como root o usando sudo"
  exit 1
fi

# -------------------------------
# INSTALAR DOCKER SI NO EXISTE
# -------------------------------
if ! command -v docker >/dev/null 2>&1; then
  echo "[INFO] Instalando Docker..."
  apt update
  apt install -y ca-certificates curl gnupg lsb-release

  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod 644 /etc/apt/keyrings/docker.gpg

  UBUNTU_CODENAME=$(lsb_release -cs)
  cat <<EOF >/etc/apt/sources.list.d/docker.list
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable
EOF

  apt update
  apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

# -------------------------------
# SELECCIONAR IP DEL SERVIDOR PARA ELK
# -------------------------------
echo "[INFO] Detectando interfaces de red disponibles para ELK Stack..."
mapfile -t IFACES < <(ip -o -4 addr show | awk '{print $2 " " $4}')

if [ ${#IFACES[@]} -eq 0 ]; then
  echo "[ERROR] No se encontraron interfaces de red con IP"
  exit 1
fi

echo "Seleccione la interfaz que usará ELK Stack (Elasticsearch y Kibana):"
for i in "${!IFACES[@]}"; do
  iface_name=$(echo "${IFACES[$i]}" | awk '{print $1}')
  iface_ip=$(echo "${IFACES[$i]}" | awk '{print $2}' | cut -d/ -f1)
  echo "[$i] $iface_name -> $iface_ip"
done

while true; do
  read -rp "Ingrese el número de la interfaz para ELK: " iface_index
  if [[ "$iface_index" =~ ^[0-9]+$ ]] && [ "$iface_index" -ge 0 ] && [ "$iface_index" -lt "${#IFACES[@]}" ]; then
    ELK_IP=$(echo "${IFACES[$iface_index]}" | awk '{print $2}' | cut -d/ -f1)
    echo "[INFO] IP seleccionada para ELK Stack: $ELK_IP"
    break
  else
    echo "[ERROR] Opción inválida, intente de nuevo."
  fi
done

# -------------------------------
# VARIABLES DE PASSWORD
# -------------------------------
read -srp "Password usuario 'elastic': " ELASTIC_PASSWORD
echo
read -srp "Password usuario 'kibana_system': " KIBANA_PASSWORD
echo

# -------------------------------
# CLAVES DE CIFRADO KIBANA
# -------------------------------
XPACK_ENCRYPTED_SAVED_OBJECTS_KEY=$(openssl rand -hex 32)
XPACK_REPORTING_KEY=$(openssl rand -hex 32)
XPACK_SECURITY_KEY=$(openssl rand -hex 32)
echo "[INFO] Claves de cifrado generadas para Kibana"

# -------------------------------
# DATOS CERTIFICADO SSL
# -------------------------------
read -rp "CN (Common Name, por ejemplo elastic.local): " CERT_CN
read -rp "O (Organization, por ejemplo Elastic): " CERT_O
read -rp "C (Country, por ejemplo ES): " CERT_C

mkdir -p certs logstash/pipeline config

# -------------------------------
# CERTIFICADOS SSL
# -------------------------------
echo "[INFO] Generando certificados SSL autofirmados..."
openssl req -x509 -newkey rsa:4096 -nodes -days 365 \
  -keyout certs/elastic.key \
  -out certs/elastic.crt \
  -subj "/CN=${CERT_CN}/O=${CERT_O}/C=${CERT_C}" \
  -addext "subjectAltName=IP:${ELK_IP}"

# Copiar certificados a servicios
for svc in kibana logstash; do
  cp certs/elastic.crt certs/${svc}.crt
  cp certs/elastic.key certs/${svc}.key
done

# -------------------------------
# CORRECCION DE PERMISOS
# -------------------------------
echo "[INFO] Ajustando permisos de certificados y claves..."
chmod 600 certs/*.key
chmod 644 certs/*.crt
chown 1000:1000 certs/*.key certs/*.crt

# -------------------------------
# KIBANA CONFIG
# -------------------------------
cat > config/kibana.yml <<EOF
server.host: "0.0.0.0"
server.ssl.enabled: true
server.ssl.certificate: /usr/share/kibana/certs/kibana.crt
server.ssl.key: /usr/share/kibana/certs/kibana.key

elasticsearch.hosts: ["https://elasticsearch:9200"]
elasticsearch.username: kibana_system
elasticsearch.password: ${KIBANA_PASSWORD}
elasticsearch.ssl.verificationMode: none

xpack.encryptedSavedObjects.encryptionKey: "${XPACK_ENCRYPTED_SAVED_OBJECTS_KEY}"
xpack.reporting.encryptionKey: "${XPACK_REPORTING_KEY}"
xpack.security.encryptionKey: "${XPACK_SECURITY_KEY}"
EOF

# -------------------------------
# ENV
# -------------------------------
cat > .env <<EOF
ELASTIC_PASSWORD=${ELASTIC_PASSWORD}
KIBANA_PASSWORD=${KIBANA_PASSWORD}
ELK_IP=${ELK_IP}
EOF

# -------------------------------
# LOGSTASH PIPELINE
# -------------------------------
cat > logstash/pipeline/syslog.conf <<EOF
input { udp { port => 1514 } }
output {
  elasticsearch {
    hosts => ["https://elasticsearch:9200"]
    user => "elastic"
    password => "${ELASTIC_PASSWORD}"
    ssl => true
    ssl_certificate_verification => false
  }
}
EOF

# -------------------------------
# DOCKER COMPOSE
# -------------------------------
cat > docker-compose.yml <<EOF
networks:
  elastic_net:
    driver: bridge

services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.15.0
    container_name: elasticsearch
    networks: [elastic_net]
    environment:
      discovery.type: single-node
      xpack.security.enabled: "true"
      xpack.security.http.ssl.enabled: "true"
      xpack.security.http.ssl.key: certs/elastic.key
      xpack.security.http.ssl.certificate: certs/elastic.crt
      ELASTIC_PASSWORD: \${ELASTIC_PASSWORD}
    volumes:
      - es_data:/usr/share/elasticsearch/data
      - ./certs:/usr/share/elasticsearch/config/certs
    ports:
      - "\${ELK_IP}:9200:9200"

  kibana:
    image: docker.elastic.co/kibana/kibana:8.15.0
    container_name: kibana
    networks: [elastic_net]
    env_file: .env
    volumes:
      - ./certs:/usr/share/kibana/certs
      - ./config/kibana.yml:/usr/share/kibana/config/kibana.yml
    ports:
      - "\${ELK_IP}:5601:5601"
    depends_on: [elasticsearch]

  logstash:
    image: docker.elastic.co/logstash/logstash:8.15.0
    container_name: logstash
    networks: [elastic_net]
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
    depends_on: [elasticsearch]

volumes:
  es_data:
EOF

# -------------------------------
# ARRANQUE
# -------------------------------
echo "[INFO] Iniciando Elasticsearch..."
docker compose up -d elasticsearch

echo "[INFO] Esperando a que Elasticsearch esté disponible..."
until docker exec elasticsearch curl -sk -u elastic:${ELASTIC_PASSWORD} https://localhost:9200 >/dev/null; do
  sleep 5
done

echo "[INFO] Cambiando password de kibana_system..."
docker exec elasticsearch curl -sk -u elastic:${ELASTIC_PASSWORD} \
  -X POST https://localhost:9200/_security/user/kibana_system/_password \
  -H "Content-Type: application/json" \
  -d "{\"password\":\"${KIBANA_PASSWORD}\"}"

echo "[INFO] Iniciando Kibana y Logstash..."
docker compose up -d

echo "[OK] ELK Stack levantado correctamente"
echo "Kibana: https://${ELK_IP}:5601"
echo "Elasticsearch: https://${ELK_IP}:9200"
