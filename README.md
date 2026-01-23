# Daily Scripts Collection

Gunluk isler icin kullanilan yardimci script koleksiyonu.

## Klasor Yapisi

```
github_ready/
├── bash_scripts/          # Bash scriptleri
│   ├── elkuser.sh         # Elasticsearch kullanici olusturma
│   ├── elk_user_local.sh  # Elasticsearch kullanici (auto IP)
│   ├── linux_readonly_user.sh  # Linux readonly kullanici
│   └── setup-elk.sh       # ELK Stack Docker kurulum
│
├── python_scripts/        # Python scriptleri
│   ├── elk_user_deploy.py # Toplu ES kullanici ekleme (SSH)
│   ├── elk_user_check.py  # ES kullanici kontrol
│   ├── elk_log_post.py    # ES'e test log gonderme
│   ├── elk_ddos_tests.py  # DDoS simulasyonu (ElastAlert test)
│   ├── system_info.py     # Sistem bilgisi (CPU/RAM/Disk)
│   ├── healthcheck.py     # URL health check
│   └── basic_fastapi_app.py  # Basit FastAPI ornegi
│
└── README.md
```

## Bash Scriptleri

### elkuser.sh
Elasticsearch'e readonly kullanici ekler. Direkt ES sunucusunda calistirilir.
- Auto localhost/IP detection
- Kullanici varsa gunceller
- viewer + kibana_user rolleri

### elk_user_local.sh
hostname -I ile IP tespit eden versiyon. localhost bind olmayan sunucularda kullanilir.

### linux_readonly_user.sh
Linux sistemde readonly kullanici olusturur.
- sudo yetkisi olmadan
- Home dizini ile
- Root yetkisi gerektirir

### setup-elk.sh
Docker Compose ile ELK Stack kurulumu.
- Elasticsearch baslatir
- kibana_system sifresi ayarlar
- Kibana baslatir

## Python Scriptleri

### elk_user_deploy.py
SSH ile birden fazla sunucuya Elasticsearch kullanici ekler.
- Paramiko ile SSH baglantisi
- Baglanti testi (Phase 1)
- Kullanici ekleme (Phase 2)
- Sonuclari dosyaya yazar

**Gereksinimler:** `pip install paramiko`

### elk_user_check.py
Sunucularda ES kullanicisinin var olup olmadigini kontrol eder.
- SSH ile baglanti
- _security/_authenticate ile dogrulama
- Detayli sonuc raporu

**Gereksinimler:** `pip install paramiko`

### elk_log_post.py
Elasticsearch'e test loglari gonderir.
- INFO, WARNING, ERROR seviyeleri
- Ornek log formati

**Gereksinimler:** `pip install elasticsearch`

### elk_ddos_tests.py
ElastAlert kurallarini test etmek icin DDoS simulasyonu.
- Faz 1: Normal trafik (30s)
- Faz 2: DDoS saldirisi (60s, 50 req/s)
- Faz 3: Recovery (20s)

**Gereksinimler:** `pip install elasticsearch`

### system_info.py
Sistem kaynaklarini goruntular.
- CPU kullanimi
- Memory kullanimi
- Disk kullanimi

**Gereksinimler:** `pip install psutil`

### healthcheck.py
URL'lerin erisilebilirligini kontrol eder.

**Gereksinimler:** `pip install requests`

### basic_fastapi_app.py
Basit FastAPI REST API ornegi.

**Gereksinimler:** `pip install fastapi uvicorn`

**Calistirma:** `uvicorn basic_fastapi_app:app --reload`

## Kullanim

1. Scriptlerdeki `YOUR_*` placeholder'larini gercek degerlerle degistirin
2. Gerekli Python paketlerini yukleyin
3. Scripti calistirin

## Guvenlik Notu

Bu scriptler hassas bilgiler icermez. Kullanmadan once asagidaki placeholder'lari guncellemeniz gerekir:

- `YOUR_SSH_USER` - SSH kullanici adi
- `YOUR_SSH_PASSWORD` - SSH sifresi
- `YOUR_ADMIN_USER` - ES admin kullanicisi
- `YOUR_ADMIN_PASSWORD` - ES admin sifresi
- `YOUR_NEW_USERNAME` - Olusturulacak kullanici
- `YOUR_NEW_PASSWORD` - Yeni kullanici sifresi
- `YOUR_ELASTICSEARCH_HOST` - ES sunucu adresi

## Lisans

Internal use only.
