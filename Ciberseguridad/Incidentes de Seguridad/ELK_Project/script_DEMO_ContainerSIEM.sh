#!/bin/bash

echo " LIMPIANDO ENTORNO ANTERIOR..."
docker compose down -v 2>/dev/null
rm -rf siem-lab

echo " CREANDO ENTORNO SIEM..."
mkdir -p siem-lab/logstash/pipeline
cd siem-lab || exit

########################################
# DOCKER COMPOSE
########################################
cat > docker-compose.yml <<'EOF'
services:

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:8.11.1
    container_name: elasticsearch
    environment:
      - discovery.type=single-node
      - xpack.security.enabled=false
      - ES_JAVA_OPTS=-Xms512m -Xmx512m
    ports:
      - "9200:9200"
    volumes:
      - es_data:/usr/share/elasticsearch/data
    networks:
      - siemnet

  kibana:
    image: docker.elastic.co/kibana/kibana:8.11.1
    container_name: kibana
    environment:
      - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    ports:
      - "5601:5601"
    depends_on:
      - elasticsearch
    networks:
      - siemnet

  logstash:
    image: docker.elastic.co/logstash/logstash:8.11.1
    container_name: logstash
    volumes:
      - ./logstash/pipeline:/usr/share/logstash/pipeline
    ports:
      - "5044:5044"
    depends_on:
      - elasticsearch
    networks:
      - siemnet

  victim:
    image: ubuntu:22.04
    container_name: victim
    command: >
      bash -c "
      apt update &&
      apt install -y openssh-server &&
      mkdir /var/run/sshd &&
      echo 'root:rootpass' | chpasswd &&
      sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config &&
      sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config &&
      echo 'LogLevel VERBOSE' >> /etc/ssh/sshd_config &&
      /usr/sbin/sshd -D -e
      "
    ports:
      - "2222:22"
    networks:
      - siemnet

  filebeat:
    image: docker.elastic.co/beats/filebeat:8.11.1
    container_name: filebeat
    user: root
    volumes:
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./filebeat.yml:/usr/share/filebeat/filebeat.yml
    depends_on:
      - logstash
    networks:
      - siemnet

  kali:
    image: kalilinux/kali-rolling
    container_name: kali
    tty: true
    stdin_open: true
    networks:
      - siemnet

volumes:
  es_data:

networks:
  siemnet:
EOF

########################################
# LOGSTASH PIPELINE
########################################
cat > logstash/pipeline/logstash.conf <<'EOF'
input {
  beats {
    port => 5044
  }
}

filter {
  if "Failed password" in [message] {
    mutate {
      add_tag => ["ssh_failed"]
    }
  }
}

output {
  elasticsearch {
    hosts => ["http://elasticsearch:9200"]
    index => "ssh-logs-%{+YYYY.MM.dd}"
  }
}
EOF

########################################
# FILEBEAT CONFIG
########################################
cat > filebeat.yml <<'EOF'
filebeat.inputs:
  - type: container
    paths:
      - /var/lib/docker/containers/*/*.log
    processors:
      - add_docker_metadata: ~

output.logstash:
  hosts: ["logstash:5044"]
EOF

# Permisos obligatorios para Filebeat
chown root:root filebeat.yml
chmod 644 filebeat.yml

echo "🚀 LEVANTANDO CONTENEDORES..."
docker compose up -d

echo ""
echo "✅ ENTORNO LISTO"
echo ""
IP=$(hostname -I | awk '{print $1}')
echo "👉 Kibana: http://$IP:5601"
echo ""
echo "Para atacar:"
echo "docker exec -it kali bash"
echo "apt update && apt install -y hydra"
echo "for i in {1..20}; do hydra -l root -p 1234 ssh://victim -t 4; done"
echo ""
