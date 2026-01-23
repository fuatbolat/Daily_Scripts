#!/bin/bash

# ELK Stack Docker Kurulum Scripti

# Ayarlar
ELASTIC_PASSWORD="YOUR_ELASTIC_PASSWORD"

echo "[*] Docker Compose ile ELK Stack baslatiliyor..."
docker-compose up -d elasticsearch

echo "[*] Elasticsearch'in hazir olmasini bekliyoruz..."
until curl -s -u elastic:$ELASTIC_PASSWORD http://localhost:9200 > /dev/null 2>&1; do
    echo "    Bekleniyor..."
    sleep 5
done
echo "[+] Elasticsearch hazir!"

# kibana_system kullanici sifresini ayarla
echo "[*] kibana_system kullanici sifresi ayarlaniyor..."
curl -s -X POST -u elastic:$ELASTIC_PASSWORD \
    "http://localhost:9200/_security/user/kibana_system/_password" \
    -H "Content-Type: application/json" \
    -d "{\"password\": \"$ELASTIC_PASSWORD\"}" > /dev/null

echo "[+] kibana_system sifresi ayarlandi"

# Kibana'yi baslat
echo "[*] Kibana baslatiliyor..."
docker-compose up -d kibana

echo "[*] Kibana'nin hazir olmasini bekliyoruz..."
until curl -s http://localhost:5601/api/status > /dev/null 2>&1; do
    echo "    Bekleniyor..."
    sleep 5
done
echo "[+] Kibana hazir!"

echo ""
echo "=========================================="
echo "[+] ELK STACK KURULUMU TAMAMLANDI!"
echo "=========================================="
echo ""
echo "Erisim Bilgileri:"
echo "  Elasticsearch: http://localhost:9200"
echo "  Kibana: http://localhost:5601"
echo ""
echo "Admin Kullanici:"
echo "  Kullanici: elastic"
echo "  Sifre: (ELASTIC_PASSWORD degiskeni)"
echo ""
echo "=========================================="
