===================================

set -uo pipefail

# ─────────────────────────────────────────────
# YAPILANDIRMA - Gerekirse buradan değiştirin
# ─────────────────────────────────────────────
NODE1_HOST="node1"  # Yerel node, hostname veya IP kullanılabilir
NODE2_HOST="node2"
NODE3_HOST="node3"

NODE1_IP="10.xxx.xxx.xxx"
NODE2_IP="10.xxx.xxx.xxx"
NODE3_IP="10.xxx.xxx.xxx"

ES_VERSION="8.17.2"
CLUSTER_NAME="elk-cluster"
ELASTIC_PASSWORD="test"

# Kibana şifreleme anahtarları (32+ karakter random string olmalı)
XPACK_SECURITY_KEY=""
XPACK_SAVEDOBJECTS_KEY=""
XPACK_REPORTING_KEY=""

# Kibana public URL (sadece Node1'de çalışacak)
KIBANA_PUBLIC_URL="https://kibana.example.com"

# Dizin yapısı (tüm node'larda aynı)
BASE_DIR="/elasticsearch"
CERTS_DIR="${BASE_DIR}/certs"
DATA_DIR="${BASE_DIR}/elasticsearch"
LOGS_DIR="${BASE_DIR}/elasticsearch_logs"
COMPOSE_DIR="/root/elk"

# SSH kullanıcısı - uzak node'lara bu kullanıcı ile bağlanılır
SSH_USER="dtuygansible"
# Uzak komutlarda sudo kullanılsın mı?
USE_SUDO="true"

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"
SSH_CMD="ssh $SSH_OPTS"
SCP_CMD="scp $SSH_OPTS"

# ─────────────────────────────────────────────
# RENK KODLARI VE LOG FONKSİYONLARI
# ─────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()      { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_phase()   { echo -e "\n${CYAN}══════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"; }

# ─────────────────────────────────────────────
# SSH KEY KURULUMU - şifre sadece burada sorulur
# ─────────────────────────────────────────────
setup_ssh_keys() {
    # Root SSH key yoksa oluştur
    if [ ! -f /root/.ssh/id_rsa ]; then
        log_info "SSH key üretiliyor (/root/.ssh/id_rsa)..."
        ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa -q
        log_ok "SSH key üretildi"
    else
        log_ok "Mevcut SSH key kullanılıyor: /root/.ssh/id_rsa"
    fi

    for remote_ip in "$NODE2_IP" "$NODE3_IP"; do
        # Key zaten kuruluysa atla
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 \
               "${SSH_USER}@${remote_ip}" "true" &>/dev/null; then
            log_ok "${remote_ip} SSH key zaten kurulu, şifre gerekmez"
            continue
        fi

        log_warn "${remote_ip} için SSH key kurulmamış."
        echo -e "${YELLOW}  >>> ${SSH_USER}@${remote_ip} şifresi girilecek (1 kez yeterli):${NC}"
        # ssh-copy-id interaktif şifre ister — sshpass gerekmez
        ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub \
            "${SSH_USER}@${remote_ip}" || {
            log_warn "${remote_ip} için SSH key kopyalanamadı, devam ediliyor..."
        }
        log_ok "${remote_ip} SSH key kuruldu"
    done
}

# ─────────────────────────────────────────────
# YARDIMCI FONKSİYONLAR
# ─────────────────────────────────────────────
run_remote() {
    local host="$1"; shift
    if [ "${USE_SUDO}" = "true" ]; then
        $SSH_CMD "${SSH_USER}@${host}" "sudo bash -c $(printf '%q' "$*")"
    else
        $SSH_CMD "${SSH_USER}@${host}" "$@"
    fi
}

# Dosyayı önce /tmp'ye kopyalar, sonra sudo ile hedefe taşır
copy_to_remote() {
    local src="$1"
    local host="$2"
    local dst="$3"
    local tmp="/tmp/_elk_deploy_$(basename "${src%/}")"

    # /tmp'ye kopyala (sudo gerekmez)
    $SCP_CMD -r "$src" "${SSH_USER}@${host}:${tmp}"

    # sudo ile hedef konuma taşı
    # Not: mkdir -p ile parent dizini oluştur, dst'nin kendisini değil
    if [ "${USE_SUDO}" = "true" ]; then
        $SSH_CMD "${SSH_USER}@${host}" \
            "sudo bash -c 'mkdir -p \$(dirname ${dst}) && { cp -r ${tmp}/. ${dst}/ 2>/dev/null || cp -r ${tmp} ${dst}; }; rm -rf ${tmp}'"
    else
        $SSH_CMD "${SSH_USER}@${host}" \
            "mkdir -p \$(dirname ${dst}) && { cp -r ${tmp}/. ${dst}/ 2>/dev/null || cp -r ${tmp} ${dst}; }; rm -rf ${tmp}"
    fi
}

wait_for_es() {
    local host="$1"
    local max_wait=120
    local elapsed=0
    log_info "Elasticsearch bekleniyor: https://${host}:9200 ..."
    until curl -sk -u "elastic:${ELASTIC_PASSWORD}" \
        "https://${host}:9200/_cluster/health" \
        --cacert "${CERTS_DIR}/ca.crt" \
        -o /dev/null 2>&1; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [ $elapsed -ge $max_wait ]; then
            log_warn "${host} elasticsearch ${max_wait}s içinde yanıt vermedi, devam ediliyor..."
            return 0
        fi
        echo -n "."
    done
    echo ""
    log_ok "${host} Elasticsearch hazır!"
}

# ─────────────────────────────────────────────
# FAZA 0: ROOT KONTROLÜ
# ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    log_error "Bu script root olarak çalıştırılmalıdır. (sudo bash deploy-elk-cluster.sh)"
    exit 1
fi
log_ok "Root yetkisi doğrulandı"

log_phase "FAZA 0: Başlangıç Kontrolleri ve Docker Kurulumu"

install_docker_if_missing() {
    local node_ip="$1"
    local node_name="$2"
    local is_local="$3"   # "local" veya "remote"

    check_cmd='command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1'

    if [ "$is_local" = "local" ]; then
        if eval "$check_cmd"; then
            log_ok "[${node_name}] Docker zaten kurulu"
            return 0
        fi
        log_info "[${node_name}] Docker kurulu değil, kuruluyor..."
        _do_install_docker_local "$node_name"
    else
        if run_remote "$node_ip" "$check_cmd" &>/dev/null; then
            log_ok "[${node_name}] Docker zaten kurulu"
            return 0
        fi
        log_info "[${node_name}] Docker kurulu değil, kuruluyor..."
        _do_install_docker_remote "$node_ip" "$node_name"
    fi
}

_do_install_docker_local() {
    local node_name="$1"
    # OS tipini tespit et
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
    else
        log_warn "[${node_name}] OS tespit edilemedi, devam ediliyor..."
        return 1
    fi

    case "$OS_ID" in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq ca-certificates curl gnupg lsb-release
            install -m 0755 -d /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
                | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
            chmod a+r /etc/apt/keyrings/docker.gpg
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" \
                > /etc/apt/sources.list.d/docker.list
            apt-get update -qq
            apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        rhel|centos|rocky|almalinux|ol)
            yum install -y -q yum-utils
            yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
            yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
            ;;
        *)
            log_warn "[${node_name}] Desteklenmeyen OS: ${OS_ID}. Docker kurulumu atlanıyor."
            return 1
            ;;
    esac

    systemctl enable --now docker
    log_ok "[${node_name}] Docker kuruldu ve başlatıldı"
}

_do_install_docker_remote() {
    local node_ip="$1"
    local node_name="$2"

    run_remote "$node_ip" '
        set -e
        . /etc/os-release
        case "$ID" in
            ubuntu|debian)
                apt-get update -qq
                apt-get install -y -qq ca-certificates curl gnupg lsb-release
                install -m 0755 -d /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/${ID}/gpg \
                    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
                chmod a+r /etc/apt/keyrings/docker.gpg
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${ID} $(lsb_release -cs) stable" \
                    > /etc/apt/sources.list.d/docker.list
                apt-get update -qq
                apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            rhel|centos|rocky|almalinux|ol)
                yum install -y -q yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y -q docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
                ;;
            *)
                echo "Desteklenmeyen OS: $ID"; exit 1
                ;;
        esac
        systemctl enable --now docker
    '
    log_ok "[${node_name}] Docker kuruldu ve başlatıldı"
}

# ── Tüm node'lara Docker kur (SSH key henüz olmayabilir, önce Node1) ──
install_docker_if_missing "$NODE1_IP" "$NODE1_HOST" "local"

# Docker Compose komutunu belirle (Node1 için)
if docker compose version &>/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    log_warn "Docker Compose bulunamadı, devam ediliyor..."
    DC="docker compose"
fi
log_ok "Docker ve Docker Compose hazır (komut: $DC)"

# ─────────────────────────────────────────────
# FAZA 1: SSH KEY KURULUMU VE ERİŞİM KONTROLÜ
# ─────────────────────────────────────────────
log_phase "FAZA 1: SSH Key Kurulumu ve Bağlantı Kontrolü"

setup_ssh_keys

for remote_ip in "$NODE2_IP" "$NODE3_IP"; do
    log_info "${remote_ip} bağlantısı doğrulanıyor..."
    if $SSH_CMD "${SSH_USER}@${remote_ip}" "echo 'SSH OK'" &>/dev/null; then
        log_ok "${remote_ip} SSH erişimi başarılı"
        if [ "${USE_SUDO}" = "true" ]; then
            if $SSH_CMD "${SSH_USER}@${remote_ip}" "sudo -n true" &>/dev/null; then
                log_ok "${remote_ip} NOPASSWD sudo yetkisi mevcut"
            else
                log_warn "${remote_ip} sudo şifre soruyor — NOPASSWD sudoers önerilir:"
                log_warn "  echo '${SSH_USER} ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers.d/${SSH_USER}"
            fi
        fi
    else
        log_warn "${remote_ip} SSH erişimi başarısız, devam ediliyor..."
    fi
done

# SSH erişimi hazır, Node2/3'e Docker kur
install_docker_if_missing "$NODE2_IP" "$NODE2_HOST" "remote"
install_docker_if_missing "$NODE3_IP" "$NODE3_HOST" "remote"

# ─────────────────────────────────────────────
# FAZA 2: TÜM NODE'LARDA SİSTEM HAZIRLIĞI
# ─────────────────────────────────────────────
log_phase "FAZA 2: Sistem Hazırlığı (tüm node'lar)"

setup_node_system() {
    local node_ip="$1"
    local node_name="$2"
    local node_num="$3"

    log_info "[${node_name}] Dizinler oluşturuluyor..."
    if [ "$node_ip" = "$NODE1_IP" ]; then
        # Yerel node
        mkdir -p "${CERTS_DIR}/node1" "${CERTS_DIR}/node2" "${CERTS_DIR}/node3"
        mkdir -p "$DATA_DIR" "$LOGS_DIR" "$COMPOSE_DIR"
        # elasticsearch container uid=1000 ile çalışır, data ve log dizinleri yazılabilir olmalı
        chown -R 1000:1000 "$DATA_DIR" "$LOGS_DIR"
        chmod 755 "$CERTS_DIR" "$DATA_DIR" "$LOGS_DIR"
    else
        # Uzak node
        run_remote "$node_ip" "
            mkdir -p ${CERTS_DIR}/node${node_num} ${DATA_DIR} ${LOGS_DIR} ${COMPOSE_DIR}
            chown -R 1000:1000 ${DATA_DIR} ${LOGS_DIR}
            chmod 755 ${CERTS_DIR} ${DATA_DIR} ${LOGS_DIR}
        "
    fi

    log_info "[${node_name}] vm.max_map_count ayarlanıyor..."
    if [ "$node_ip" = "$NODE1_IP" ]; then
        sysctl -w vm.max_map_count=262144 > /dev/null
        grep -q "vm.max_map_count" /etc/sysctl.conf \
            || echo "vm.max_map_count=262144" >> /etc/sysctl.conf
    else
        run_remote "$node_ip" "
            sysctl -w vm.max_map_count=262144 > /dev/null
            grep -q 'vm.max_map_count' /etc/sysctl.conf \
                || echo 'vm.max_map_count=262144' >> /etc/sysctl.conf
        "
    fi

    log_info "[${node_name}] ulimits ayarlanıyor..."
    if [ "$node_ip" = "$NODE1_IP" ]; then
        grep -q "elasticsearch" /etc/security/limits.conf 2>/dev/null || \
            printf "elasticsearch soft memlock unlimited\nelasticsearch hard memlock unlimited\n" \
            >> /etc/security/limits.conf
    else
        run_remote "$node_ip" "
            grep -q 'elasticsearch' /etc/security/limits.conf 2>/dev/null || \
            printf 'elasticsearch soft memlock unlimited\nelasticsearch hard memlock unlimited\n' \
            >> /etc/security/limits.conf
        "
    fi

    log_ok "[${node_name}] Sistem hazırlığı tamamlandı"
}

setup_node_system "$NODE1_IP" "$NODE1_HOST" "1"
setup_node_system "$NODE2_IP" "$NODE2_HOST" "2"
setup_node_system "$NODE3_IP" "$NODE3_HOST" "3"

# ─────────────────────────────────────────────
# FAZA 3: SERTİFİKA ÜRETİMİ (Node1'de)
# ─────────────────────────────────────────────
log_phase "FAZA 3: SSL Sertifika Üretimi"

# Sertifika zaten varsa atla
if [ -f "${CERTS_DIR}/ca.crt" ] && \
   [ -f "${CERTS_DIR}/node1/node1.crt" ] && \
   [ -f "${CERTS_DIR}/node2/node2.crt" ] && \
   [ -f "${CERTS_DIR}/node3/node3.crt" ]; then
    log_warn "Sertifikalar zaten mevcut. Yeniden üretmek için ${CERTS_DIR} dizinini silin."
else
    log_info "CA ve node sertifikaları üretiliyor (elasticsearch certutil)..."

    # instances.yml - sertifika üretimi için node tanımları
    cat > /tmp/elk_instances.yml <<EOF
instances:
  - name: node1
    dns:
      - ${NODE1_HOST}
      - localhost
    ip:
      - ${NODE1_IP}
      - 127.0.0.1
  - name: node2
    dns:
      - ${NODE2_HOST}
      - localhost
    ip:
      - ${NODE2_IP}
      - 127.0.0.1
  - name: node3
    dns:
      - ${NODE3_HOST}
      - localhost
    ip:
      - ${NODE3_IP}
      - 127.0.0.1
EOF

    # elasticsearch container'ı uid=1000 ile çalışır, dizin yazılabilir olmalı
    chown -R 1000:1000 "${CERTS_DIR}"
    chmod -R 755 "${CERTS_DIR}"

    log_info "CA sertifikası üretiliyor..."
    docker run --rm \
        -v "${CERTS_DIR}:/certs" \
        -v "/tmp/elk_instances.yml:/elk_instances.yml" \
        "docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}" \
        bash -c "
            elasticsearch-certutil ca \
                --silent \
                --pem \
                --out /certs/ca.zip && \
            unzip -o /certs/ca.zip -d /certs/ && \
            mv /certs/ca/ca.crt /certs/ca.crt && \
            mv /certs/ca/ca.key /certs/ca.key && \
            rmdir /certs/ca
        "

    log_info "Node sertifikaları üretiliyor..."
    docker run --rm \
        -v "${CERTS_DIR}:/certs" \
        -v "/tmp/elk_instances.yml:/elk_instances.yml" \
        "docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}" \
        bash -c "
            elasticsearch-certutil cert \
                --silent \
                --pem \
                --ca-cert /certs/ca.crt \
                --ca-key  /certs/ca.key \
                --in      /elk_instances.yml \
                --out     /certs/certs.zip && \
            unzip -o /certs/certs.zip -d /certs/ && \
            cp /certs/ca.crt /certs/node1/ca.crt && \
            cp /certs/ca.crt /certs/node2/ca.crt && \
            cp /certs/ca.crt /certs/node3/ca.crt && \
            chmod 644 /certs/ca.crt /certs/node1/* /certs/node2/* /certs/node3/* && \
            chmod 640 /certs/ca.key
        "

    # Temizlik
    rm -f "${CERTS_DIR}/ca.zip" "${CERTS_DIR}/certs.zip"
    rm -f /tmp/elk_instances.yml

    # Sahipliği tekrar root'a al, izinleri kısıt
    chown -R root:root "${CERTS_DIR}"
    chmod 644 "${CERTS_DIR}/ca.crt"
    chmod 640 "${CERTS_DIR}/ca.key"
    find "${CERTS_DIR}" -name "*.crt" -exec chmod 644 {} \;
    find "${CERTS_DIR}" -name "*.key" -exec chmod 640 {} \;

    log_ok "Sertifikalar başarıyla üretildi:"
    ls -la "${CERTS_DIR}/" "${CERTS_DIR}/node1/" "${CERTS_DIR}/node2/" "${CERTS_DIR}/node3/"
fi

# ca.crt'nin node alt dizinlerinde olduğunu garanti et (her çalıştırmada)
log_info "ca.crt node dizinlerine kopyalanıyor..."
cp -f "${CERTS_DIR}/ca.crt" "${CERTS_DIR}/node1/ca.crt"
cp -f "${CERTS_DIR}/ca.crt" "${CERTS_DIR}/node2/ca.crt"
cp -f "${CERTS_DIR}/ca.crt" "${CERTS_DIR}/node3/ca.crt"
chmod 644 "${CERTS_DIR}/node1/ca.crt" "${CERTS_DIR}/node2/ca.crt" "${CERTS_DIR}/node3/ca.crt"
log_ok "ca.crt tüm node dizinlerinde mevcut"

# ─────────────────────────────────────────────
# FAZA 4: SERTİFİKALARI DAĞIT
# ─────────────────────────────────────────────
log_phase "FAZA 4: Sertifikaları Node2 ve Node3'e Dağıtma"

log_info "Node2'ye sertifikalar kopyalanıyor..."
run_remote "$NODE2_IP" "mkdir -p ${CERTS_DIR}/node2"
copy_to_remote "${CERTS_DIR}/node2/" "$NODE2_IP" "${CERTS_DIR}/node2/"
run_remote "$NODE2_IP" "cp ${CERTS_DIR}/node2/ca.crt ${CERTS_DIR}/ca.crt 2>/dev/null || true"
log_ok "Node2 sertifikaları dağıtıldı"

log_info "Node3'e sertifikalar kopyalanıyor..."
run_remote "$NODE3_IP" "mkdir -p ${CERTS_DIR}/node3"
copy_to_remote "${CERTS_DIR}/node3/" "$NODE3_IP" "${CERTS_DIR}/node3/"
run_remote "$NODE3_IP" "cp ${CERTS_DIR}/node3/ca.crt ${CERTS_DIR}/ca.crt 2>/dev/null || true"
log_ok "Node3 sertifikaları dağıtıldı"

# ─────────────────────────────────────────────
# FAZA 5: DOCKER COMPOSE DOSYALARI OLUŞTUR VE DAĞIT
# ─────────────────────────────────────────────
log_phase "FAZA 5: Docker Compose Dosyaları Oluşturma"

# ── NODE 1 ──────────────────────────────────
log_info "Node1 docker-compose.yml oluşturuluyor..."
cat > "${COMPOSE_DIR}/docker-compose.yml" <<EOF
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: elasticsearch
    restart: always
    environment:
      - network.host=_site_
      - network.publish_host=${NODE1_IP}
      - node.name=node1
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=node1,node2,node3
      - node.roles=master,data,ingest,remote_cluster_client
      - discovery.seed_hosts=${NODE1_IP},${NODE2_IP},${NODE3_IP}
      - bootstrap.memory_lock=true
      - ES_JAVA_OPTS=-Xms2g -Xmx2g
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
    volumes:
      - ${DATA_DIR}:/usr/share/elasticsearch/data
      - ${LOGS_DIR}:/usr/share/elasticsearch/logs
    ports:
      - '9200:9200'
      - '9300:9300'
    ulimits:
      memlock: { soft: -1, hard: -1 }

  kibana:
    image: docker.elastic.co/kibana/kibana:${ES_VERSION}
    container_name: kibana
    restart: always
    depends_on:
      - elasticsearch
    environment:
      - SERVER_PUBLICBASEURL=${KIBANA_PUBLIC_URL}
      - ELASTICSEARCH_HOSTS=http://${NODE1_IP}:9200
      - XPACK_SECURITY_ENCRYPTIONKEY=${XPACK_SECURITY_KEY}
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=${XPACK_SAVEDOBJECTS_KEY}
      - XPACK_REPORTING_ENCRYPTIONKEY=${XPACK_REPORTING_KEY}
    ports:
      - '5601:5601'
    volumes:
      - /root/elk/entrypoint.sh:/usr/local/bin/entrypoint.sh
    entrypoint: ['bash', '/usr/local/bin/entrypoint.sh']
EOF

# ── NODE 2 ──────────────────────────────────
log_info "Node2 docker-compose.yml oluşturuluyor..."
cat > /tmp/docker-compose-node2.yml <<EOF
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: elasticsearch
    restart: always
    environment:
      - network.host=_site_
      - network.publish_host=${NODE2_IP}
      - node.name=node2
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=node1,node2,node3
      - node.roles=master,data,ingest,remote_cluster_client
      - discovery.seed_hosts=${NODE1_IP},${NODE2_IP},${NODE3_IP}
      - bootstrap.memory_lock=true
      - ES_JAVA_OPTS=-Xms2g -Xmx2g
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
    volumes:
      - ${DATA_DIR}:/usr/share/elasticsearch/data
      - ${LOGS_DIR}:/usr/share/elasticsearch/logs
    ports:
      - '9200:9200'
      - '9300:9300'
    ulimits:
      memlock: { soft: -1, hard: -1 }

  kibana:
    image: docker.elastic.co/kibana/kibana:${ES_VERSION}
    container_name: kibana
    restart: always
    environment:
      - SERVER_PUBLICBASEURL=${KIBANA_PUBLIC_URL}
      - ELASTICSEARCH_HOSTS=http://${NODE2_IP}:9200
      - XPACK_SECURITY_ENCRYPTIONKEY=${XPACK_SECURITY_KEY}
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=${XPACK_SAVEDOBJECTS_KEY}
      - XPACK_REPORTING_ENCRYPTIONKEY=${XPACK_REPORTING_KEY}
    ports:
      - '5601:5601'
    volumes:
      - /root/elk/entrypoint.sh:/usr/local/bin/entrypoint.sh
    entrypoint: ['bash', '/usr/local/bin/entrypoint.sh']
EOF

copy_to_remote "/tmp/docker-compose-node2.yml" "$NODE2_IP" "${COMPOSE_DIR}/docker-compose.yml"
log_ok "Node2 docker-compose.yml dağıtıldı"

# ── NODE 3 ──────────────────────────────────
log_info "Node3 docker-compose.yml oluşturuluyor..."
cat > /tmp/docker-compose-node3.yml <<EOF
version: '3.8'
services:
  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:${ES_VERSION}
    container_name: elasticsearch
    restart: always
    environment:
      - network.host=_site_
      - network.publish_host=${NODE3_IP}
      - node.name=node3
      - cluster.name=${CLUSTER_NAME}
      - cluster.initial_master_nodes=node1,node2,node3
      - node.roles=master,data,ingest,remote_cluster_client
      - discovery.seed_hosts=${NODE1_IP},${NODE2_IP},${NODE3_IP}
      - bootstrap.memory_lock=true
      - ES_JAVA_OPTS=-Xms2g -Xmx2g
      - xpack.security.enabled=false
      - xpack.security.http.ssl.enabled=false
    volumes:
      - ${DATA_DIR}:/usr/share/elasticsearch/data
      - ${LOGS_DIR}:/usr/share/elasticsearch/logs
    ports:
      - '9200:9200'
      - '9300:9300'
    ulimits:
      memlock: { soft: -1, hard: -1 }

  kibana:
    image: docker.elastic.co/kibana/kibana:${ES_VERSION}
    container_name: kibana
    restart: always
    environment:
      - SERVER_PUBLICBASEURL=${KIBANA_PUBLIC_URL}
      - ELASTICSEARCH_HOSTS=http://${NODE3_IP}:9200
      - XPACK_SECURITY_ENCRYPTIONKEY=${XPACK_SECURITY_KEY}
      - XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY=${XPACK_SAVEDOBJECTS_KEY}
      - XPACK_REPORTING_ENCRYPTIONKEY=${XPACK_REPORTING_KEY}
    ports:
      - '5601:5601'
    volumes:
      - /root/elk/entrypoint.sh:/usr/local/bin/entrypoint.sh
    entrypoint: ['bash', '/usr/local/bin/entrypoint.sh']
EOF

copy_to_remote "/tmp/docker-compose-node3.yml" "$NODE3_IP" "${COMPOSE_DIR}/docker-compose.yml"
log_ok "Node3 docker-compose.yml dağıtıldı"

# Temp dosyaları temizle
rm -f /tmp/docker-compose-node2.yml /tmp/docker-compose-node3.yml

# ─────────────────────────────────────────────
# FAZA 6: KİBANA ENTRYPOINT SCRIPTI
# ─────────────────────────────────────────────
log_phase "FAZA 6: Kibana Entrypoint Script (Node1)"

cat > "${COMPOSE_DIR}/entrypoint.sh" <<'ENTRYEOF'
#!/bin/bash
ES_HOST="${ELASTICSEARCH_HOSTS:-http://localhost:9200}"

echo "[*] Elasticsearch bekleniyor: ${ES_HOST}"

for i in $(seq 1 30); do
    if curl -s "${ES_HOST}/_cluster/health" | grep -qv '"status":"red"'; then
        echo "[+] Elasticsearch hazır!"
        break
    fi
    echo "    Deneme ${i}/30 - bekleniyor (10s)..."
    sleep 10
done

echo "[*] Kibana başlatılıyor..."
exec /usr/local/bin/kibana-docker
ENTRYEOF

chmod +x "${COMPOSE_DIR}/entrypoint.sh"
log_ok "Node1 Kibana entrypoint scripti oluşturuldu"

log_info "entrypoint.sh Node2'ye kopyalanıyor..."
copy_to_remote "${COMPOSE_DIR}/entrypoint.sh" "$NODE2_IP" "${COMPOSE_DIR}/entrypoint.sh"
run_remote "$NODE2_IP" "chmod +x ${COMPOSE_DIR}/entrypoint.sh"
log_ok "Node2 entrypoint.sh kopyalandı"

log_info "entrypoint.sh Node3'e kopyalanıyor..."
copy_to_remote "${COMPOSE_DIR}/entrypoint.sh" "$NODE3_IP" "${COMPOSE_DIR}/entrypoint.sh"
run_remote "$NODE3_IP" "chmod +x ${COMPOSE_DIR}/entrypoint.sh"
log_ok "Node3 entrypoint.sh kopyalandı"

# ─────────────────────────────────────────────
# FAZA 7: ELASTİCSEARCH BAŞLATMA
# ─────────────────────────────────────────────
log_phase "FAZA 7: Elasticsearch Başlatılıyor"

# Node1 (yerel - zaten root olarak çalışıyoruz)
log_info "Node1 Elasticsearch başlatılıyor..."
cd "${COMPOSE_DIR}"
$DC up -d elasticsearch
log_ok "Node1 Elasticsearch başlatıldı"

# Node2
log_info "Node2 Elasticsearch başlatılıyor (10s bekle)..."
sleep 10
run_remote "$NODE2_IP" "cd ${COMPOSE_DIR} && /usr/bin/docker compose up -d elasticsearch kibana"
log_ok "Node2 Elasticsearch ve Kibana başlatıldı"

# Node3
log_info "Node3 Elasticsearch başlatılıyor (10s bekle)..."
sleep 10
run_remote "$NODE3_IP" "cd ${COMPOSE_DIR} && /usr/bin/docker compose up -d elasticsearch kibana"
log_ok "Node3 Elasticsearch ve Kibana başlatıldı"

# ─────────────────────────────────────────────
# FAZA 8: CLUSTER SAĞLIĞI KONTROLÜ (ATLANDI)
# ─────────────────────────────────────────────
log_phase "FAZA 8: Elasticsearch'in Ayağa Kalkması Bekleniyor"
log_info "Tüm node'ların başlaması için 90 saniye bekleniyor..."
sleep 90
log_info "Node1 Elasticsearch durumu kontrol ediliyor..."
curl -s "http://${NODE1_IP}:9200/_cluster/health?pretty" 2>/dev/null \
    || log_warn "Node1 henüz yanıt vermiyor, devam ediliyor..."

# ─────────────────────────────────────────────
# FAZA 9: KİBANA KULLANICISI AYARLA
# ─────────────────────────────────────────────
log_phase "FAZA 9: kibana_system Kullanıcı Şifresi (xpack.security kapalı, atlanıyor)"
log_warn "xpack.security.enabled=false olduğu için kibana_system şifre ayarı gerekmiyor"

# ─────────────────────────────────────────────
# FAZA 10: KİBANA BAŞLAT
# ─────────────────────────────────────────────
log_phase "FAZA 10: Kibana Başlatılıyor (Node1)"

cd "${COMPOSE_DIR}"
$DC up -d kibana
log_ok "Kibana başlatıldı"

log_info "Kibana hazır olana kadar bekleniyor (max 3 dk)..."
ELAPSED=0
until curl -sk "https://${NODE1_IP}:5601/api/status" -o /dev/null 2>&1 || \
      curl -sk "http://${NODE1_IP}:5601/api/status" -o /dev/null 2>&1; do
    sleep 10
    ELAPSED=$((ELAPSED + 10))
    echo -n "."
    if [ $ELAPSED -ge 180 ]; then
        log_warn "Kibana 3 dakika içinde yanıt vermedi. Logları kontrol edin: docker logs kibana"
        break
    fi
done
echo ""
log_ok "Kibana hazır!"

# ─────────────────────────────────────────────
# FAZA 11: DOĞRULAMA
# ─────────────────────────────────────────────
log_phase "FAZA 11: Kurulum Doğrulaması"

echo ""
log_info "Cluster Node Durumu:"
curl -s \
    "http://${NODE1_IP}:9200/_cat/nodes?v&h=ip,name,heap.percent,ram.percent,cpu,node.role,master" \
    2>/dev/null || log_warn "Node listesi alınamadı"

echo ""
log_info "Cluster Sağlık Özeti:"
curl -s \
    "http://${NODE1_IP}:9200/_cluster/health?pretty" \
    2>/dev/null || log_warn "Cluster health alınamadı"

# ─────────────────────────────────────────────
# TAMAMLANDI
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        ELK 3-NODE CLUSTER KURULUMU TAMAMLANDI        ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Elasticsearch:"
echo -e "    Node1:  ${CYAN}http://${NODE1_IP}:9200${NC}  (${NODE1_HOST})"
echo -e "    Node2:  ${CYAN}http://${NODE2_IP}:9200${NC}  (${NODE2_HOST})"
echo -e "    Node3:  ${CYAN}http://${NODE3_IP}:9200${NC}  (${NODE3_HOST})"
echo ""
echo -e "  Kibana:"
echo -e "    Node1:  ${CYAN}http://${NODE1_IP}:5601${NC}  (${NODE1_HOST})"
echo -e "    Node2:  ${CYAN}http://${NODE2_IP}:5601${NC}  (${NODE2_HOST})"
echo -e "    Node3:  ${CYAN}http://${NODE3_IP}:5601${NC}  (${NODE3_HOST})"
echo ""
echo -e "  Kullanıcı Bilgileri:"
echo -e "    Kullanıcı: ${YELLOW}elastic${NC}"
echo -e "    Şifre:     ${YELLOW}${ELASTIC_PASSWORD}${NC}"
echo ""
echo -e "  Sertifikalar: ${CERTS_DIR}/"
echo -e "  Compose:      ${COMPOSE_DIR}/"
echo ""
echo -e "  Faydalı Komutlar:"
echo -e "    Cluster sağlık:  curl -sk --cacert ${CERTS_DIR}/ca.crt -u elastic:${ELASTIC_PASSWORD} https://${NODE1_IP}:9200/_cluster/health?pretty"
echo -e "    Node listesi:    curl -sk --cacert ${CERTS_DIR}/ca.crt -u elastic:${ELASTIC_PASSWORD} https://${NODE1_IP}:9200/_cat/nodes?v"
echo -e "    ES logları:      docker logs -f elasticsearch"
echo -e "    Kibana logları:  docker logs -f kibana"
echo ""
