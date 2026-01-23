#!/usr/bin/env python3
"""
Elasticsearch Kullanici Kontrol Scripti
Sunucularda belirtilen kullanicinin var olup olmadigini kontrol eder
"""

import paramiko
import sys

# ========== AYARLAR ==========

# SSH Bilgileri
SSH_USER = "YOUR_SSH_USER"
SSH_PASS = "YOUR_SSH_PASSWORD"
SSH_PORT = 22

# Kontrol edilecek kullanici
CHECK_USER = "YOUR_CHECK_USERNAME"
CHECK_PASS = "YOUR_CHECK_PASSWORD"

# Sunucu Listesi
SERVERS = [
    "10.0.0.1",
    "10.0.0.2",
    # Sunucu IP adreslerini buraya ekleyin
]

# ========== SCRIPT ==========

def check_user_exists(ssh, server):
    """Elasticsearch'te kullanici var mi kontrol et"""

    command = f'''
    ES_HOST=$(hostname -I | awk '{{print $1}}')
    curl -s -u "{CHECK_USER}:{CHECK_PASS}" "http://$ES_HOST:9200/_security/_authenticate" 2>/dev/null
    '''

    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()

    if CHECK_USER in output and "username" in output:
        return True, "Kullanici mevcut ve giris yapabiliyor"
    elif "security_exception" in output:
        return False, "Kullanici yok veya sifre yanlis"
    elif "no handler found" in output:
        return False, "Security modulu kapali"
    else:
        return False, output[:100] if output else "Bos yanit"

def main():
    print("=" * 70)
    print("  Elasticsearch Kullanici Kontrol Scripti")
    print("=" * 70)
    print(f"  Kontrol Edilecek Kullanici: {CHECK_USER}")
    print(f"  Sunucu Sayisi: {len(SERVERS)}")
    print("=" * 70)
    print()

    found_servers = []
    not_found_servers = []
    error_servers = []

    for server in SERVERS:
        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(server, port=SSH_PORT, username=SSH_USER, password=SSH_PASS, timeout=10)

            exists, message = check_user_exists(ssh, server)

            if exists:
                print(f"[+] {server} - MEVCUT")
                found_servers.append(server)
            else:
                print(f"[-] {server} - YOK ({message})")
                not_found_servers.append((server, message))

            ssh.close()

        except Exception as e:
            print(f"[!] {server} - HATA: {e}")
            error_servers.append((server, str(e)))

    # Ozet
    print()
    print("=" * 70)
    print("  SONUC OZETI")
    print("=" * 70)
    print(f"  Toplam Sunucu: {len(SERVERS)}")
    print(f"  Kullanici Mevcut: {len(found_servers)}")
    print(f"  Kullanici Yok: {len(not_found_servers)}")
    print(f"  Hata: {len(error_servers)}")
    print("=" * 70)

    # Detaylar
    if found_servers:
        print()
        print("[+] KULLANICI MEVCUT OLAN SUNUCULAR:")
        for server in found_servers:
            print(f"    {server}")

    if not_found_servers:
        print()
        print("[-] KULLANICI OLMAYAN SUNUCULAR:")
        for server, reason in not_found_servers:
            print(f"    {server} - {reason}")

    if error_servers:
        print()
        print("[!] HATA ALINAN SUNUCULAR:")
        for server, error in error_servers:
            print(f"    {server} - {error}")

    # Dosyaya yaz
    with open("elk_user_check_result.txt", "w") as f:
        f.write(f"# Elasticsearch Kullanici Kontrol Sonuclari\n")
        f.write(f"# Kullanici: {CHECK_USER}\n")
        f.write(f"# Tarih: {__import__('datetime').datetime.now()}\n\n")

        f.write(f"MEVCUT ({len(found_servers)}):\n")
        for server in found_servers:
            f.write(f"  {server}\n")

        f.write(f"\nYOK ({len(not_found_servers)}):\n")
        for server, reason in not_found_servers:
            f.write(f"  {server} - {reason}\n")

        f.write(f"\nHATA ({len(error_servers)}):\n")
        for server, error in error_servers:
            f.write(f"  {server} - {error}\n")

    print()
    print("[*] Sonuclar 'elk_user_check_result.txt' dosyasina yazildi")

if __name__ == "__main__":
    main()
