#!/usr/bin/env python3
"""
IIS DDoS Attack Simulator
ElastAlert test icin DDoS saldirisi simulasyonu yapar
"""

from elasticsearch import Elasticsearch
from datetime import datetime
import random
import time

# Ayarlar
ES_HOST = "YOUR_ELASTICSEARCH_HOST"
ES_PORT = 9200
ATTACKER_IP = "192.168.100.66"
INDEX_NAME = "iis-logs"

NORMAL_IPS = ["10.0.0.5", "10.0.0.12", "10.0.0.23"]
ENDPOINTS = ["/", "/api/login", "/api/products", "/admin"]
STATUS_NORMAL = [200, 201, 301, 404]
STATUS_ATTACK = [429, 503, 504]

print("=" * 50)
print("    IIS DDoS ATTACK SIMULATOR")
print("    ElastAlert Demo")
print("=" * 50 + "\n")

# Elasticsearch baglantisi
es = Elasticsearch([f'http://{ES_HOST}:{ES_PORT}'])
if not es.ping():
    print("[!] Elasticsearch'e baglanilamadi!")
    exit(1)
print("[+] Elasticsearch baglantisi basarili\n")

# Index olustur
mapping = {
    "mappings": {
        "properties": {
            "timestamp": {"type": "date"},
            "client_ip": {"type": "ip"},
            "server_name": {"type": "keyword"},
            "log_type": {"type": "keyword"}
        }
    }
}
try:
    es.indices.create(index=INDEX_NAME, mappings=mapping["mappings"])
    print(f"[+] Index '{INDEX_NAME}' olusturuldu\n")
except Exception as e:
    if "already exists" in str(e).lower() or "resource_already_exists" in str(e).lower():
        print(f"[+] Index '{INDEX_NAME}' zaten mevcut\n")
    else:
        print(f"[!] Hata: {e}")
        exit(1)

# Faz 1: Normal trafik (30 saniye)
print("="*50)
print("[>] FAZ 1: Normal Trafik (30 saniye)")
print("="*50)
start = time.time()
count = 0
while time.time() - start < 30:
    log = {
        "timestamp": datetime.now().isoformat(),
        "server_name": "iis-web-01",
        "client_ip": random.choice(NORMAL_IPS),
        "endpoint": random.choice(ENDPOINTS),
        "status_code": random.choice(STATUS_NORMAL),
        "log_type": "iis_access"
    }
    es.index(index=INDEX_NAME, document=log)
    count += 1
    print(f"   OK Normal log #{count}", end='\r')
    time.sleep(random.uniform(0.5, 2))

print(f"\n[+] {count} normal log gonderildi\n")
time.sleep(2)

# Faz 2: DDoS Saldirisi (60 saniye)
print("="*50)
print("[!!] FAZ 2: DDoS SALDIRISI (60 saniye)")
print("="*50)
print(f"[*] Saldirgan IP: {ATTACKER_IP}")
print(f"[*] Hiz: 50 req/saniye")
print("="*50 + "\n")

start = time.time()
total = 0
while time.time() - start < 60:
    for _ in range(50):
        log = {
            "timestamp": datetime.now().isoformat(),
            "server_name": "iis-web-01",
            "client_ip": ATTACKER_IP,
            "endpoint": random.choice(ENDPOINTS),
            "status_code": random.choice(STATUS_ATTACK),
            "log_type": "iis_access"
        }
        es.index(index=INDEX_NAME, document=log)
        total += 1

    elapsed = int(time.time() - start)
    print(f"   [ATTACK] Saldiri: {elapsed}/60s - {total} request", end='\r')
    time.sleep(1)

print(f"\n[+] {total} saldiri logu gonderildi\n")
time.sleep(2)

# Faz 3: Recovery (20 saniye)
print("="*50)
print("[>] FAZ 3: Saldiri Sonrasi Normal Trafik")
print("="*50)
start = time.time()
count = 0
while time.time() - start < 20:
    log = {
        "timestamp": datetime.now().isoformat(),
        "server_name": "iis-web-01",
        "client_ip": random.choice(NORMAL_IPS),
        "endpoint": random.choice(ENDPOINTS),
        "status_code": random.choice(STATUS_NORMAL),
        "log_type": "iis_access"
    }
    es.index(index=INDEX_NAME, document=log)
    count += 1
    print(f"   OK Normal log #{count}", end='\r')
    time.sleep(random.uniform(1, 2.5))

print(f"\n[+] {count} normal log gonderildi\n")

# Ozet
print("\n" + "="*50)
print("[+] DEMO TAMAMLANDI!")
print("="*50)
print(f"\n[>] Saldirgan IP: {ATTACKER_IP}")
print(f"\n[~] ElastAlert 1-2 dakika icinde alert uretecek")
print(f"   Komut: docker logs -f elastalert\n")
print("="*50 + "\n")
