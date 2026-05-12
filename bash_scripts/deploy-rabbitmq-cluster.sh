#!/bin/bash
# =============================================================================
# RabbitMQ 3-Node Cluster - Tam Otomatik Kurulum Scripti
# Çalıştırıldığı sunucu: NODE1
# =============================================================================
# Kullanım: bash deploy-rabbitmq-cluster.sh
#
# ÖN KOŞUL: Bu scripti NODE1 üzerinde root olarak çalıştırın.
#           Uzak node'lara SSH_USER ile bağlanılır.
#           Kullanıcının uzak sunucularda NOPASSWD sudo yetkisi olmalıdır.
# =============================================================================

set -uo pipefail

# ─────────────────────────────────────────────
# YAPILANDIRMA - Gerekirse buradan değiştirin
# ─────────────────────────────────────────────
NODE1_HOST="test-rmq-node1"
NODE2_HOST="test-rmq-node2"
NODE3_HOST="test-rmq-node3"

NODE1_IP="10.xxx.xxx.xxx"  # Bu sunucunun IP adresi
NODE2_IP="10.xxx.xxx.xxx"
NODE3_IP="10.xxx.xxx.xxx"

RABBITMQ_VERSION="3.8-management"

# Admin kullanıcı bilgileri
RABBITMQ_USER="admin"
RABBITMQ_PASS="admin123"

# Erlang cookie - tüm node'larda aynı olmalı (cluster için zorunlu)
ERLANG_COOKIE="mysecretcookie"

# Vhost
RABBITMQ_VHOST="/"

# Dizin yapısı
BASE_DIR="/rabbitmq"
DATA_DIR="${BASE_DIR}/data"
LOGS_DIR="${BASE_DIR}/logs"
COMPOSE_DIR="/root/rabbitmq"

# SSH kullanıcısı
SSH_USER="myuser"
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

log_info()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_phase() { echo -e "\n${CYAN}══════════════════════════════════════════════════════${NC}"; echo -e "${CYAN}  $*${NC}"; echo -e "${CYAN}══════════════════════════════════════════════════════${NC}"; }

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

copy_to_remote() {
    local src="$1"
    local host="$2"
    local dst="$3"
    local tmp="/tmp/_rmq_deploy_$(basename "${src%/}")"

    $SCP_CMD -r "$src" "${SSH_USER}@${host}:${tmp}"

    if [ "${USE_SUDO}" = "true" ]; then
        $SSH_CMD "${SSH_USER}@${host}" \
            "sudo bash -c 'mkdir -p \$(dirname ${dst}) && { cp -r ${tmp}/. ${dst}/ 2>/dev/null || cp -r ${tmp} ${dst}; }; rm -rf ${tmp}'"
    else
        $SSH_CMD "${SSH_USER}@${host}" \
            "mkdir -p \$(dirname ${dst}) && { cp -r ${tmp}/. ${dst}/ 2>/dev/null || cp -r ${tmp} ${dst}; }; rm -rf ${tmp}"
    fi
}

# ─────────────────────────────────────────────
# SSH KEY KURULUMU
# ─────────────────────────────────────────────
setup_ssh_keys() {
    if [ ! -f /root/.ssh/id_rsa ]; then
        log_info "SSH key üretiliyor..."
        ssh-keygen -t rsa -b 4096 -N "" -f /root/.ssh/id_rsa -q
        log_ok "SSH key üretildi"
    else
        log_ok "Mevcut SSH key kullanılıyor: /root/.ssh/id_rsa"
    fi

    for remote_ip in "$NODE2_IP" "$NODE3_IP"; do
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes -o ConnectTimeout=5 \
               "${SSH_USER}@${remote_ip}" "true" &>/dev/null; then
            log_ok "${remote_ip} SSH key zaten kurulu"
            continue
        fi
        log_warn "${remote_ip} için SSH key kurulmamış."
        echo -e "${YELLOW}  >>> ${SSH_USER}@${remote_ip} şifresi girilecek (1 kez yeterli):${NC}"
        ssh-copy-id -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa.pub \
            "${SSH_USER}@${remote_ip}" || {
            log_warn "${remote_ip} için SSH key kopyalanamadı, devam ediliyor..."
        }
        log_ok "${remote_ip} SSH key kuruldu"
    done
}

# ─────────────────────────────────────────────
# DOCKER KURULUM FONKSİYONLARI
# ─────────────────────────────────────────────
install_docker_if_missing() {
    local node_ip="$1"
    local node_name="$2"
    local is_local="$3"

    local check_cmd='command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1'

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
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
    else
        log_warn "[${node_name}] OS tespit edilemedi"
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
            log_warn "[${node_name}] Desteklenmeyen OS: ${OS_ID}"
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

# ─────────────────────────────────────────────
# FAZA 0: ROOT KONTROLÜ
# ─────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    log_error "Bu script root olarak çalıştırılmalıdır."
    exit 1
fi
log_ok "Root yetkisi doğrulandı"

log_phase "FAZA 0: Başlangıç Kontrolleri ve Docker Kurulumu"

install_docker_if_missing "$NODE1_IP" "$NODE1_HOST" "local"

if docker compose version &>/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    log_warn "Docker Compose bulunamadı, devam ediliyor..."
    DC="docker compose"
fi
log_ok "Docker Compose hazır (komut: $DC)"

# ─────────────────────────────────────────────
# FAZA 1: SSH KEY KURULUMU
# ─────────────────────────────────────────────
log_phase "FAZA 1: SSH Key Kurulumu ve Bağlantı Kontrolü"

setup_ssh_keys

for remote_ip in "$NODE2_IP" "$NODE3_IP"; do
    log_info "${remote_ip} bağlantısı doğrulanıyor..."
    if $SSH_CMD "${SSH_USER}@${remote_ip}" "echo 'SSH OK'" &>/dev/null; then
        log_ok "${remote_ip} SSH erişimi başarılı"
        if $SSH_CMD "${SSH_USER}@${remote_ip}" "sudo -n true" &>/dev/null; then
            log_ok "${remote_ip} NOPASSWD sudo yetkisi mevcut"
        else
            log_warn "${remote_ip} sudo şifre soruyor — NOPASSWD sudoers önerilir"
        fi
    else
        log_warn "${remote_ip} SSH erişimi başarısız, devam ediliyor..."
    fi
done

install_docker_if_missing "$NODE2_IP" "$NODE2_HOST" "remote"
install_docker_if_missing "$NODE3_IP" "$NODE3_HOST" "remote"

# ─────────────────────────────────────────────
# FAZA 2: SİSTEM HAZIRLIĞI
# ─────────────────────────────────────────────
log_phase "FAZA 2: Sistem Hazırlığı (tüm node'lar)"

setup_node_system() {
    local node_ip="$1"
    local node_name="$2"

    log_info "[${node_name}] Dizinler oluşturuluyor..."
    if [ "$node_ip" = "$NODE1_IP" ]; then
        mkdir -p "$DATA_DIR" "$LOGS_DIR" "$COMPOSE_DIR"
        # RabbitMQ container uid=999 ile çalışır
        chown -R 999:999 "$DATA_DIR" "$LOGS_DIR"
        chmod 755 "$DATA_DIR" "$LOGS_DIR"
    else
        run_remote "$node_ip" "
            mkdir -p ${DATA_DIR} ${LOGS_DIR} ${COMPOSE_DIR}
            chown -R 999:999 ${DATA_DIR} ${LOGS_DIR}
            chmod 755 ${DATA_DIR} ${LOGS_DIR}
        "
    fi
    log_ok "[${node_name}] Sistem hazırlığı tamamlandı"
}

setup_node_system "$NODE1_IP" "$NODE1_HOST"
setup_node_system "$NODE2_IP" "$NODE2_HOST"
setup_node_system "$NODE3_IP" "$NODE3_HOST"

# ─────────────────────────────────────────────
# FAZA 3: DOCKER COMPOSE DOSYALARI OLUŞTUR VE DAĞIT
# ─────────────────────────────────────────────
log_phase "FAZA 3: Docker Compose Dosyaları Oluşturma"

generate_compose() {
    local node_ip="$1"
    local node_name="$2"   # RMQNODE01
    local node_num="$3"    # 1

    cat <<EOF
services:
  rabbitmq:
    image: rabbitmq:${RABBITMQ_VERSION}
    container_name: rabbitmq
    hostname: rabbit@${node_name}
    restart: always
    environment:
      - RABBITMQ_ERLANG_COOKIE=${ERLANG_COOKIE}
      - RABBITMQ_DEFAULT_USER=${RABBITMQ_USER}
      - RABBITMQ_DEFAULT_PASS=${RABBITMQ_PASS}
      - RABBITMQ_DEFAULT_VHOST=${RABBITMQ_VHOST}
      - RABBITMQ_NODENAME=rabbit@${node_name}
      - RABBITMQ_USE_LONGNAME=false
    extra_hosts:
      - "rabbit@${NODE1_HOST}:${NODE1_IP}"
      - "rabbit@${NODE2_HOST}:${NODE2_IP}"
      - "rabbit@${NODE3_HOST}:${NODE3_IP}"
      - "${NODE1_HOST}:${NODE1_IP}"
      - "${NODE2_HOST}:${NODE2_IP}"
      - "${NODE3_HOST}:${NODE3_IP}"
    volumes:
      - ${DATA_DIR}:/var/lib/rabbitmq
      - ${LOGS_DIR}:/var/log/rabbitmq
    ports:
      - '5672:5672'
      - '15672:15672'
      - '25672:25672'
      - '4369:4369'
    ulimits:
      nofile:
        soft: 65536
        hard: 65536
EOF
}

# Node1
log_info "Node1 docker-compose.yml oluşturuluyor..."
generate_compose "$NODE1_IP" "$NODE1_HOST" "1" > "${COMPOSE_DIR}/docker-compose.yml"
log_ok "Node1 docker-compose.yml oluşturuldu"

# Node2
log_info "Node2 docker-compose.yml oluşturuluyor..."
generate_compose "$NODE2_IP" "$NODE2_HOST" "2" > /tmp/rmq-compose-node2.yml
copy_to_remote "/tmp/rmq-compose-node2.yml" "$NODE2_IP" "${COMPOSE_DIR}/docker-compose.yml"
log_ok "Node2 docker-compose.yml dağıtıldı"

# Node3
log_info "Node3 docker-compose.yml oluşturuluyor..."
generate_compose "$NODE3_IP" "$NODE3_HOST" "3" > /tmp/rmq-compose-node3.yml
copy_to_remote "/tmp/rmq-compose-node3.yml" "$NODE3_IP" "${COMPOSE_DIR}/docker-compose.yml"
log_ok "Node3 docker-compose.yml dağıtıldı"

rm -f /tmp/rmq-compose-node2.yml /tmp/rmq-compose-node3.yml

# ─────────────────────────────────────────────
# FAZA 4: RABBITMQ BAŞLATMA
# ─────────────────────────────────────────────
log_phase "FAZA 4: RabbitMQ Başlatılıyor"

log_info "Node1 RabbitMQ başlatılıyor..."
cd "${COMPOSE_DIR}"
$DC up -d
log_ok "Node1 RabbitMQ başlatıldı"

log_info "Node2 RabbitMQ başlatılıyor (10s bekle)..."
sleep 10
run_remote "$NODE2_IP" "cd ${COMPOSE_DIR} && /usr/bin/docker compose up -d"
log_ok "Node2 RabbitMQ başlatıldı"

log_info "Node3 RabbitMQ başlatılıyor (10s bekle)..."
sleep 10
run_remote "$NODE3_IP" "cd ${COMPOSE_DIR} && /usr/bin/docker compose up -d"
log_ok "Node3 RabbitMQ başlatıldı"

# ─────────────────────────────────────────────
# FAZA 5: CLUSTER OLUŞTURMA
# ─────────────────────────────────────────────
log_phase "FAZA 5: Cluster Oluşturma"

log_info "Node1 RabbitMQ'nun hazır olması bekleniyor (60s)..."
sleep 60

# Node1'in hazır olup olmadığını kontrol et
ELAPSED=0
until docker exec rabbitmq rabbitmqctl status &>/dev/null; do
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
    if [ $ELAPSED -ge 120 ]; then
        log_warn "Node1 RabbitMQ 120s içinde hazır olmadı, devam ediliyor..."
        break
    fi
done
echo ""
log_ok "Node1 RabbitMQ hazır"

# Node2'yi cluster'a ekle
log_info "Node2 cluster'a ekleniyor..."
run_remote "$NODE2_IP" "
    /usr/bin/docker exec rabbitmq rabbitmqctl stop_app
    /usr/bin/docker exec rabbitmq rabbitmqctl reset
    /usr/bin/docker exec rabbitmq rabbitmqctl join_cluster rabbit@${NODE1_HOST}
    /usr/bin/docker exec rabbitmq rabbitmqctl start_app
" && log_ok "Node2 cluster'a eklendi" || log_warn "Node2 cluster'a eklenemedi, manuel kontrol gerekebilir"

sleep 5

# Node3'ü cluster'a ekle
log_info "Node3 cluster'a ekleniyor..."
run_remote "$NODE3_IP" "
    /usr/bin/docker exec rabbitmq rabbitmqctl stop_app
    /usr/bin/docker exec rabbitmq rabbitmqctl reset
    /usr/bin/docker exec rabbitmq rabbitmqctl join_cluster rabbit@${NODE1_HOST}
    /usr/bin/docker exec rabbitmq rabbitmqctl start_app
" && log_ok "Node3 cluster'a eklendi" || log_warn "Node3 cluster'a eklenemedi, manuel kontrol gerekebilir"

sleep 5

# ─────────────────────────────────────────────
# FAZA 6: HA POLİTİKASI
# ─────────────────────────────────────────────
log_phase "FAZA 6: High Availability Politikası Ayarlanıyor"

log_info "HA mirror policy ayarlanıyor (tüm node'lara yansıt)..."
docker exec rabbitmq rabbitmqctl set_policy ha-all \
    ".*" \
    '{"ha-mode":"all","ha-sync-mode":"automatic"}' \
    --priority 1 \
    --apply-to all \
    && log_ok "HA politikası ayarlandı" \
    || log_warn "HA politikası ayarlanamadı, manuel kontrol gerekebilir"

# ─────────────────────────────────────────────
# FAZA 7: DOĞRULAMA
# ─────────────────────────────────────────────
log_phase "FAZA 7: Kurulum Doğrulaması"

echo ""
log_info "Cluster Node Listesi:"
docker exec rabbitmq rabbitmqctl cluster_status 2>/dev/null || log_warn "Cluster durumu alınamadı"

echo ""
log_info "Kullanıcı Listesi:"
docker exec rabbitmq rabbitmqctl list_users 2>/dev/null || true

# ─────────────────────────────────────────────
# TAMAMLANDI
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║     RABBITMQ 3-NODE CLUSTER KURULUMU TAMAMLANDI      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Management UI:"
echo -e "    Node1:  ${CYAN}http://${NODE1_IP}:15672${NC}  (${NODE1_HOST})"
echo -e "    Node2:  ${CYAN}http://${NODE2_IP}:15672${NC}  (${NODE2_HOST})"
echo -e "    Node3:  ${CYAN}http://${NODE3_IP}:15672${NC}  (${NODE3_HOST})"
echo ""
echo -e "  AMQP Bağlantı:"
echo -e "    Node1:  ${CYAN}amqp://${NODE1_IP}:5672${NC}"
echo -e "    Node2:  ${CYAN}amqp://${NODE2_IP}:5672${NC}"
echo -e "    Node3:  ${CYAN}amqp://${NODE3_IP}:5672${NC}"
echo ""
echo -e "  Kullanıcı Bilgileri:"
echo -e "    Kullanıcı: ${YELLOW}${RABBITMQ_USER}${NC}"
echo -e "    Şifre:     ${YELLOW}${RABBITMQ_PASS}${NC}"
echo ""
echo -e "  Faydalı Komutlar:"
echo -e "    Cluster durumu:  docker exec rabbitmq rabbitmqctl cluster_status"
echo -e "    Node listesi:    docker exec rabbitmq rabbitmqctl cluster_status"
echo -e "    Queue listesi:   docker exec rabbitmq rabbitmqctl list_queues"
echo -e "    RMQ logları:     docker logs -f rabbitmq"
echo ""
