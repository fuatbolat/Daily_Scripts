#!/bin/nsh
# ==============================================================================
# KAFKA & ZOOKEEPER UÇTAN UCA OTOMASYON BETİĞİ (NSH)
# ==============================================================================
# Açıklama: Root yetkileriyle temiz kurulum ve servis yapılandırması sağlar.
# Parametreler: $1 = Zookeeper Host List, $2 = Kafka Broker Host List
# ==============================================================================

ZOO_HOST_LIST=$1
BROKER_HOST_LIST=$2
IP_PROP_NAME="IP_ADDRESS"

# Kaynak Dosya Yolları
ZOO_SOURCE="//DTEKAPPANSIBLET01.fw.dteknoloji.com.tr/var/lib/awx/projects/kafka/apache-zookeeper-3.8.3-bin.tar.gz"
KAFKA_SOURCE="//DTEKAPPANSIBLET01.fw.dteknoloji.com.tr/var/lib/awx/projects/kafka/kafka_2.13-3.6.0.tgz"

# Yardımcı Fonksiyonlar (Daha temiz loglama için)
print_banner() { echo "\n==============================================================================\n>>> $1\n=============================================================================="; }
print_status() { echo "[$(date +%H:%M:%S)] $1"; }

# ------------------------------------------------------------------------------
# 1. ENVANTER VE NETWORK HAZIRLIĞI
# ------------------------------------------------------------------------------
print_banner "1. ENVANTER VE NETWORK HAZIRLIĞI"

HOSTS_TO_PROCESS=$(echo "$ZOO_HOST_LIST,$BROKER_HOST_LIST" | tr ',' '\n' | sed '/^$/d' | sort -u)
ZOO_HOSTS=$(echo "$ZOO_HOST_LIST" | tr ',' '\n' | sed '/^$/d')
BROKER_HOSTS=$(echo "$BROKER_HOST_LIST" | tr ',' '\n' | sed '/^$/d')

HOSTS_ENTRIES=""
ZOOKEEPER_CONNECT=""
ZOO_SERVER_LINES=""

# IP ve Hostname eşleştirmelerini topla
for HOST in $HOSTS_TO_PROCESS; do
    IP=$(blcli Server printPropertyValue $HOST "$IP_PROP_NAME")
    if [ -n "$IP" ]; then
        HOSTS_ENTRIES="${HOSTS_ENTRIES}${IP} ${HOST%%.*} ${HOST}\n"
    fi
done

# Zookeeper Cluster String oluşturma
ID_COUNTER=0
for HOST in $ZOO_HOSTS; do
    ID_COUNTER=$((ID_COUNTER + 1))
    IP=$(blcli Server printPropertyValue $HOST "$IP_PROP_NAME")
    [ -n "$ZOOKEEPER_CONNECT" ] && ZOOKEEPER_CONNECT="$ZOOKEEPER_CONNECT,"
    ZOOKEEPER_CONNECT="${ZOOKEEPER_CONNECT}${IP}:2181"
    ZOO_SERVER_LINES="${ZOO_SERVER_LINES}\nserver.${ID_COUNTER}=${IP}:2888:3888"
done

print_status "Network topolojisi çıkarıldı. Toplam $(echo "$HOSTS_TO_PROCESS" | wc -l) sunucu işlenecek."

# ------------------------------------------------------------------------------
# 2. GLOBAL /etc/hosts GÜNCELLEME
# ------------------------------------------------------------------------------
for HOST in $HOSTS_TO_PROCESS; do
    print_status "$HOST: /etc/hosts güncelleniyor..."
    nexec $HOST sh -c "perl -i -pe 'undef \$_ if /^# KAFKA\/ZOOKEEPER SETUP ENTRY/ .. eof' /etc/hosts"
    nexec $HOST sh -c "printf \"\n# KAFKA/ZOOKEEPER SETUP ENTRY\n$HOSTS_ENTRIES\" >> /etc/hosts"
done

# ------------------------------------------------------------------------------
# 3. ZOOKEEPER KURULUMU
# ------------------------------------------------------------------------------
if [ -n "$ZOO_HOST_LIST" ]; then
    print_banner "2. ZOOKEEPER CLUSTER KURULUMU"
    ID_COUNTER=0
    for HOST in $ZOO_HOSTS; do
        ID_COUNTER=$((ID_COUNTER + 1))
        echo "--- [ Node: $HOST | ID: $ID_COUNTER ] ---"

        print_status "Bağımlılıklar kuruluyor (Java 17)..."
        nexec $HOST sh -c "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-17-jre-headless > /dev/null 2>&1"

        print_status "Dosyalar kopyalanıyor ve açılıyor..."
        nexec $HOST sh -c "rm -rf /kafka/zookeeper && mkdir -p /kafka/zookeeper"
        cp "$ZOO_SOURCE" //"$HOST"/tmp/
        nexec $HOST sh -c "tar -xzf /tmp/apache-zookeeper-3.8.3-bin.tar.gz -C /kafka/zookeeper/ && rm /tmp/apache-zookeeper-3.8.3-bin.tar.gz"

        print_status "Yetkilendirme (Root/755) ve Yapılandırma..."
        nexec $HOST sh -c "chown -R root:root /kafka/zookeeper && chmod -R 755 /kafka/zookeeper"
        nexec $HOST sh -c "printf \"dataDir=/kafka/zookeeper/data\nclientPort=2181\ntickTime=2000\ninitLimit=10\nsyncLimit=5$ZOO_SERVER_LINES\" > /kafka/zookeeper/apache-zookeeper-3.8.3-bin/conf/zoo.cfg"
        nexec $HOST sh -c "mkdir -p /kafka/zookeeper/data && echo $ID_COUNTER > /kafka/zookeeper/data/myid && chmod 644 /kafka/zookeeper/data/myid"

        print_status "Servis oluşturuluyor ve başlatılıyor..."
        nexec $HOST sh -c "cat > /etc/systemd/system/zookeeper.service << EOF
[Unit]
Description=Zookeeper Service
After=network-online.target
[Service]
User=root
WorkingDirectory=/kafka/zookeeper/apache-zookeeper-3.8.3-bin/
ExecStart=/kafka/zookeeper/apache-zookeeper-3.8.3-bin/bin/zkServer.sh start-foreground
ExecStop=/kafka/zookeeper/apache-zookeeper-3.8.3-bin/bin/zkServer.sh stop
Restart=on-failure
[Install]
WantedBy=multi-user.target
"
        nexec $HOST sh -c "systemctl daemon-reload && systemctl enable --now zookeeper.service > /dev/null 2>&1"
    done
    print_status "Cluster senkronizasyonu için 15 saniye bekleniyor..."
    sleep 15
fi

# ------------------------------------------------------------------------------
# 4. KAFKA BROKER KURULUMU
# ------------------------------------------------------------------------------
if [ -n "$BROKER_HOST_LIST" ]; then
    print_banner "3. KAFKA BROKER KURULUMU"
    ID_COUNTER=0
    for HOST in $BROKER_HOSTS; do
        ID_COUNTER=$((ID_COUNTER + 1))
        echo "--- [ Broker: $HOST | ID: $ID_COUNTER ] ---"

        print_status "Java 17 kuruluyor..."
        nexec $HOST sh -c "DEBIAN_FRONTEND=noninteractive apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq openjdk-17-jre-headless > /dev/null 2>&1"

        print_status "Binari dosyalar aktarılıyor..."
        nexec $HOST sh -c "rm -rf /kafka/broker && mkdir -p /kafka/broker/log"
        cp "$KAFKA_SOURCE" //"$HOST"/tmp/
        nexec $HOST sh -c "tar -xzf /tmp/kafka_2.13-3.6.0.tgz -C /kafka/broker/ && rm /tmp/kafka_2.13-3.6.0.tgz"

        print_status "İzinler ve server.properties ayarlanıyor..."
        nexec $HOST sh -c "chown -R root:root /kafka/broker && chmod -R 755 /kafka/broker"
        nexec $HOST sh -c "cat > /kafka/broker/kafka_2.13-3.6.0/config/server.properties << EOF
broker.id=$ID_COUNTER
listeners=PLAINTEXT://:9092
log.dirs=/kafka/broker/log
num.partitions=3
zookeeper.connect=$ZOOKEEPER_CONNECT
offsets.topic.replication.factor=2
default.replication.factor=3
min.insync.replicas=2
auto.create.topics.enable=true
delete.topic.enable=true
"

        print_status "Kafka servisi yapılandırılıyor..."
        nexec $HOST sh -c "cat > /etc/systemd/system/kafka.service << EOF
[Unit]
Description=Kafka Broker
After=network-online.target zookeeper.service
[Service]
User=root
WorkingDirectory=/kafka/broker/kafka_2.13-3.6.0/
ExecStart=/kafka/broker/kafka_2.13-3.6.0/bin/kafka-server-start.sh /kafka/broker/kafka_2.13-3.6.0/config/server.properties
ExecStop=/kafka/broker/kafka_2.13-3.6.0/bin/kafka-server-stop.sh
Restart=always
[Install]
WantedBy=multi-user.target
"
        nexec $HOST sh -c "systemctl daemon-reload && systemctl enable --now kafka.service > /dev/null 2>&1"
    done
fi

print_banner "KURULUM TAMAMLANDI 🎉"
print_status "Zookeeper: $ZOOKEEPER_CONNECT"
print_status "Tüm servisler root yetkisiyle başlatıldı."