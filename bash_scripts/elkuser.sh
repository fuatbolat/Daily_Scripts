#!/bin/bash

# Elasticsearch Readonly Kullanici Olusturma Scripti
# Bu script direkt Elasticsearch sunucusunda calistirilir

# Elasticsearch baglanti bilgileri
# Sunucu IP'sini otomatik bul (localhost calismiyorsa)
ES_HOST=$(hostname -I | awk '{print $1}')
ES_PORT="9200"
ES_ADMIN_USER="YOUR_ADMIN_USER"
ES_ADMIN_PASS="YOUR_ADMIN_PASSWORD"

# localhost dene, calismiyorsa IP kullan
if curl -s -u "$ES_ADMIN_USER:$ES_ADMIN_PASS" "http://localhost:$ES_PORT" > /dev/null 2>&1; then
    ES_HOST="localhost"
    echo "[*] localhost uzerinden baglaniliyor..."
else
    echo "[*] $ES_HOST uzerinden baglaniliyor..."
fi

# Olusturulacak readonly kullanici bilgileri
NEW_USER="YOUR_NEW_USERNAME"
NEW_PASS="YOUR_NEW_PASSWORD"

# Kullanici var mi kontrol et
echo "[*] Kullanici kontrol ediliyor..."
USER_EXISTS=$(curl -s -u "$ES_ADMIN_USER:$ES_ADMIN_PASS" \
    "http://$ES_HOST:$ES_PORT/_security/user/$NEW_USER" \
    -w "%{http_code}" -o /dev/null)

if [ "$USER_EXISTS" == "200" ]; then
    echo "[*] Kullanici '$NEW_USER' zaten mevcut - Guncelleniyor..."
else
    echo "[*] Kullanici '$NEW_USER' bulunamadi - Olusturuluyor..."
fi

# Readonly kullanici olustur/guncelle
echo "[*] Elasticsearch'e kullanici ekleniyor..."
RESPONSE=$(curl -s -X PUT -u "$ES_ADMIN_USER:$ES_ADMIN_PASS" \
    "http://$ES_HOST:$ES_PORT/_security/user/$NEW_USER" \
    -H "Content-Type: application/json" \
    -d "{
        \"password\": \"$NEW_PASS\",
        \"roles\": [\"viewer\", \"kibana_user\"],
        \"full_name\": \"ReadOnly User\",
        \"email\": \"readonly@local\"
    }")

# Sonucu kontrol et
if echo "$RESPONSE" | grep -q '"created":true'; then
    echo "[+] Kullanici '$NEW_USER' basariyla olusturuldu"
elif echo "$RESPONSE" | grep -q '"created":false'; then
    echo "[+] Kullanici '$NEW_USER' basariyla guncellendi"
else
    echo "[!] Hata: $RESPONSE"
    exit 1
fi

# Kullaniciyi dogrula
echo ""
echo "[*] Kullanici dogrulaniyor..."
VERIFY=$(curl -s -u "$NEW_USER:$NEW_PASS" "http://$ES_HOST:$ES_PORT/_security/_authenticate")

if echo "$VERIFY" | grep -q "\"username\":\"$NEW_USER\""; then
    echo "[+] Dogrulama basarili!"
    echo ""
    echo "Kullanici Bilgileri:"
    echo "  Kullanici Adi: $NEW_USER"
    echo "  Roller: viewer, kibana_user (readonly + kibana erisimi)"
    echo ""
    echo "Erisim:"
    echo "  Elasticsearch: curl -u $NEW_USER:*** http://$ES_HOST:$ES_PORT/_cat/indices"
    echo "  Kibana: http://<kibana_ip>:5601 (ayni kullanici/sifre ile giris yapin)"
else
    echo "[!] Dogrulama basarisiz!"
    echo "$VERIFY"
    exit 1
fi

echo ""
echo "[+] Islem tamamlandi"
