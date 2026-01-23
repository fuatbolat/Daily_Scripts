#!/usr/bin/env python3
"""
Elasticsearch Readonly Kullanici Toplu Ekleme Scripti
SSH ile sunuculara baglanip Elasticsearch'e kullanici ekler
"""

import paramiko
import sys

# ========== AYARLAR ==========

# SSH Bilgileri
SSH_USER = "YOUR_SSH_USER"
SSH_PASS = "YOUR_SSH_PASSWORD"
SSH_PORT = 22

# Elasticsearch Admin Bilgileri
ES_ADMIN_USER = "YOUR_ES_ADMIN_USER"
ES_ADMIN_PASS = "YOUR_ES_ADMIN_PASSWORD"

# Olusturulacak Kullanici
ES_NEW_USER = "YOUR_NEW_USERNAME"
ES_NEW_PASS = "YOUR_NEW_PASSWORD"

# Sunucu Listesi
SERVERS = [
    "10.0.0.1",
    "10.0.0.2",
    # Sunucu IP adreslerini buraya ekleyin
]

# ========== SCRIPT ==========

def test_ssh_connection(server):
    """SSH baglantisi test et"""
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(server, port=SSH_PORT, username=SSH_USER, password=SSH_PASS, timeout=10)
        ssh.close()
        return True, None
    except paramiko.AuthenticationException:
        return False, "SSH kimlik dogrulama hatasi"
    except paramiko.SSHException as e:
        return False, f"SSH hatasi: {e}"
    except Exception as e:
        return False, f"Baglanti hatasi: {e}"

def create_elk_user(ssh, server_ip):
    """Elasticsearch'e readonly kullanici ekler"""

    command = f'''
    ES_HOST=$(hostname -I | awk '{{print $1}}')

    curl -s -X PUT -u "{ES_ADMIN_USER}:{ES_ADMIN_PASS}" \
        "http://$ES_HOST:9200/_security/user/{ES_NEW_USER}" \
        -H "Content-Type: application/json" \
        -d '{{
            "password": "{ES_NEW_PASS}",
            "roles": ["viewer", "kibana_user"],
            "full_name": "ReadOnly User"
        }}'
    '''

    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()
    error = stderr.read().decode()

    return output, error

def verify_user(ssh, server_ip):
    """Kullanici olusturuldu mu kontrol et"""

    command = f'''
    ES_HOST=$(hostname -I | awk '{{print $1}}')
    curl -s -u "{ES_NEW_USER}:{ES_NEW_PASS}" "http://$ES_HOST:9200/_security/_authenticate"
    '''

    stdin, stdout, stderr = ssh.exec_command(command)
    output = stdout.read().decode()

    return ES_NEW_USER in output

def main():
    print("=" * 60)
    print("  Elasticsearch Readonly Kullanici Toplu Ekleme")
    print("=" * 60)
    print(f"  SSH Kullanici: {SSH_USER}")
    print(f"  ES Kullanici: {ES_NEW_USER}")
    print(f"  Sunucu Sayisi: {len(SERVERS)}")
    print("=" * 60)
    print()

    # Baglanti testi
    print("[*] ADIM 1: SSH Baglanti Testi")
    print("-" * 60)

    reachable_servers = []
    unreachable_servers = []

    for server in SERVERS:
        success, error = test_ssh_connection(server)
        if success:
            print(f"[+] {server} - OK")
            reachable_servers.append(server)
        else:
            print(f"[!] {server} - HATA: {error}")
            unreachable_servers.append((server, error))

    print()
    print(f"[*] Baglanti Ozeti: {len(reachable_servers)} basarili, {len(unreachable_servers)} basarisiz")
    print()

    # Baglanamayanlar
    if unreachable_servers:
        print("-" * 60)
        print("[!] BAGLANAMAYAN SUNUCULAR:")
        print("-" * 60)
        for server, error in unreachable_servers:
            print(f"    {server} - {error}")
        print()

        # Dosyaya yaz
        with open("unreachable_servers.txt", "w") as f:
            f.write("# SSH Baglantisi Yapilamayan Sunucular\n")
            f.write(f"# Tarih: {__import__('datetime').datetime.now()}\n\n")
            for server, error in unreachable_servers:
                f.write(f"{server} - {error}\n")
        print("[*] Baglanamayan sunucular 'unreachable_servers.txt' dosyasina yazildi")
        print()

    if not reachable_servers:
        print("[!] Hicbir sunucuya baglanilamadi!")
        sys.exit(1)

    # Kullanici ekleme
    print("-" * 60)
    print("[*] ADIM 2: Elasticsearch Kullanici Ekleme")
    print("-" * 60)

    success_count = 0
    fail_count = 0
    failed_servers = []

    for server in reachable_servers:
        print(f"[*] {server} - Kullanici olusturuluyor...")

        try:
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            ssh.connect(server, port=SSH_PORT, username=SSH_USER, password=SSH_PASS, timeout=10)

            output, error = create_elk_user(ssh, server)

            if verify_user(ssh, server):
                print(f"[+] {server} - Basarili")
                success_count += 1
            else:
                print(f"[!] {server} - Kullanici olusturulamadi")
                print(f"    Cikti: {output[:200] if output else 'Bos'}")
                fail_count += 1
                failed_servers.append((server, output))

            ssh.close()

        except Exception as e:
            print(f"[!] {server} - Hata: {e}")
            fail_count += 1
            failed_servers.append((server, str(e)))

    # Basarisiz olanlar
    if failed_servers:
        with open("failed_elk_users.txt", "w") as f:
            f.write("# Elasticsearch Kullanici Eklenemyen Sunucular\n")
            f.write(f"# Tarih: {__import__('datetime').datetime.now()}\n\n")
            for server, error in failed_servers:
                f.write(f"{server}\n  Hata: {error[:200] if error else 'Bilinmiyor'}\n\n")
        print()
        print("[*] Basarisiz sunucular 'failed_elk_users.txt' dosyasina yazildi")

    # Ozet
    print()
    print("=" * 60)
    print("  SONUC OZETI")
    print("=" * 60)
    print(f"  Toplam Sunucu: {len(SERVERS)}")
    print(f"  SSH Basarili: {len(reachable_servers)}")
    print(f"  SSH Basarisiz: {len(unreachable_servers)}")
    print(f"  Kullanici Eklenen: {success_count}")
    print(f"  Kullanici Eklenemeyen: {fail_count}")
    print("=" * 60)

    if unreachable_servers or failed_servers:
        print()
        print("Detaylar icin:")
        if unreachable_servers:
            print("  - unreachable_servers.txt")
        if failed_servers:
            print("  - failed_elk_users.txt")

if __name__ == "__main__":
    main()
