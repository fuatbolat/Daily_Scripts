#!/usr/bin/env python3
"""
Elasticsearch Test Log Gonderme Scripti
Elasticsearch'e ornek log kayitlari gonderir
"""

from elasticsearch import Elasticsearch
from datetime import datetime

# Elasticsearch baglantisi
ES_HOST = "YOUR_ELASTICSEARCH_HOST"
ES_PORT = 9200

es = Elasticsearch([f'http://{ES_HOST}:{ES_PORT}'])

# Test loglari
test_logs = [
    {
        "timestamp": datetime.now().isoformat(),
        "level": "INFO",
        "message": "Test log 1 - Sistem basariyla baslatildi",
        "service": "test-service",
        "host": "server-01"
    },
    {
        "timestamp": datetime.now().isoformat(),
        "level": "WARNING",
        "message": "Test log 2 - Disk kullanimi %75'i gecti",
        "service": "test-service",
        "host": "server-01"
    },
    {
        "timestamp": datetime.now().isoformat(),
        "level": "ERROR",
        "message": "Test log 3 - Baglanti hatasi olustu",
        "service": "test-service",
        "host": "server-02"
    }
]

# Loglari gonder
print("[*] Test loglari gonderiliyor...")
for i, log in enumerate(test_logs, 1):
    result = es.index(index='test-logs', document=log)
    print(f"[+] Log {i} gonderildi - ID: {result['_id']}")

print("\n[+] Tum loglar gonderildi!")
print(f"[i] Kontrol: http://{ES_HOST}:{ES_PORT}/test-logs/_search")
