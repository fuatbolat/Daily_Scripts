#!/bin/bash

# Elasticsearch Kullanici Olusturma Scripti (Lokal Sunucu)
# Auto IP detection ile calisan versiyon

# Ayarlar
ELASTIC_HOST="http://$(hostname -I | awk '{print $1}'):9200"
ADMIN_USER="YOUR_ADMIN_USER"
ADMIN_PASS="YOUR_ADMIN_PASSWORD"
USERNAME="YOUR_NEW_USERNAME"
PASSWORD="YOUR_NEW_PASSWORD"

echo "[*] $ELASTIC_HOST uzerinden baglaniliyor..."

# Baglanti testi
if ! curl -s -u "$ADMIN_USER:$ADMIN_PASS" "$ELASTIC_HOST" > /dev/null 2>&1; then
    echo "[!] Elasticsearch'e baglanilamadi!"
    echo "[!] Host: $ELASTIC_HOST"
    exit 1
fi
echo "[+] Baglanti basarili"

# Kullanici kontrol
echo "[*] Kullanici kontrol ediliyor..."
USER_EXISTS=$(curl -s -u "$ADMIN_USER:$ADMIN_PASS" \
    "$ELASTIC_HOST/_security/user/$USERNAME" \
    -w "%{http_code}" -o /dev/null)

if [ "$USER_EXISTS" == "200" ]; then
    echo "[*] Kullanici '$USERNAME' mevcut - Guncelleniyor..."
else
    echo "[*] Kullanici '$USERNAME' bulunamadi - Olusturuluyor..."
fi

# Readonly kullanici olustur/guncelle
echo "[*] Kullanici ekleniyor..."
RESPONSE=$(curl -s -X PUT -u "$ADMIN_USER:$ADMIN_PASS" \
    "$ELASTIC_HOST/_security/user/$USERNAME" \
    -H "Content-Type: application/json" \
    -d "{
        \"password\": \"$PASSWORD\",
        \"roles\": [\"viewer\", \"kibana_user\"],
        \"full_name\": \"ReadOnly User\"

    }")

# Sonuc kontrol
if echo "$RESPONSE" | grep -q '"created":true'; then
    echo "[+] Kullanici '$USERNAME' basariyla olusturuldu"
elif echo "$RESPONSE" | grep -q '"created":false'; then
    echo "[+] Kullanici '$USERNAME' basariyla guncellendi"
else
    echo "[!] Hata: $RESPONSE"
    exit 1
fi

# Dogrulama
echo "[*] Kullanici dogrulaniyor..."
VERIFY=$(curl -s -u "$USERNAME:$PASSWORD" "$ELASTIC_HOST/_security/_authenticate")

if echo "$VERIFY" | grep -q "\"username\":\"$USERNAME\""; then
    echo "[+] Dogrulama basarili!"
    echo ""
    echo "Kullanici Bilgileri:"
    echo "  Kullanici: $USERNAME"
    echo "  Roller: viewer, kibana_user"
    echo ""
    echo "Kibana Erisimi:"
    echo "  URL: http://$(hostname -I | awk '{print $1}'):5601"
    echo "  Kullanici: $USERNAME"
else
    echo "[!] Dogrulama basarisiz!"
    echo "$VERIFY"
    exit 1
fi

echo ""
echo "[+] Islem tamamlandi"
