#!/bin/bash

# Linux Readonly Kullanici Olusturma Scripti

set -e

USERNAME="YOUR_USERNAME"
PASSWORD="YOUR_PASSWORD"

# Root yetkisi kontrolu
if [ "$EUID" -ne 0 ]; then
    echo "[!] Bu script root yetkisi ile calistirilmalidir!"
    echo "Kullanim: sudo $0"
    exit 1
fi

# Kullanici kontrol
if id "$USERNAME" &>/dev/null; then
    echo "[*] Kullanici '$USERNAME' mevcut - Sifre degistiriliyor..."
    echo "$USERNAME:$PASSWORD" | chpasswd
    echo "[+] Sifre basariyla degistirildi"
else
    echo "[*] Kullanici '$USERNAME' bulunamadi - Olusturuluyor..."

    # Readonly kullanici olustur
    useradd -m -s /bin/bash -c "ReadOnly User" "$USERNAME"
    echo "$USERNAME:$PASSWORD" | chpasswd

    # Readonly yetkilerini ayarla
    if groups "$USERNAME" | grep -q sudo; then
        gpasswd -d "$USERNAME" sudo &>/dev/null
    fi

    chmod 750 /home/$USERNAME
    mkdir -p /home/$USERNAME/.ssh
    chmod 700 /home/$USERNAME/.ssh
    chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh

    echo "[+] Kullanici basariyla olusturuldu"
fi

# Dogrulama
echo ""
echo "[*] Kullanici dogrulaniyor..."
if id "$USERNAME" &>/dev/null; then
    echo "[+] Kullanici mevcut: $(id $USERNAME)"
else
    echo "[!] Kullanici olusturulamadi!"
    exit 1
fi

echo "[+] Islem tamamlandi"
