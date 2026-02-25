"""
UptimeRobot - Toplu Monitor Timeout Güncelleme Scripti
Tüm monitörlerin request timeout değerini belirtilen değere günceller.

Kullanım:
  python update_timeout.py

Gereksinimler:
  pip install requests
"""

import requests
import time
import sys

# =============================================
# AYARLAR - Buraya kendi değerlerinizi girin
# =============================================
API_KEY = ""       # UptimeRobot Ana API Anahtarı (Account > API Settings)
NEW_TIMEOUT = 60                     # Yeni timeout değeri (saniye)
DRY_RUN = False                       # True = sadece listeler, False = gerçekten günceller
SKIP_FIRST = 0                      # Kaldığı yerden devam: ilk N monitörü atla (0 = baştan başla)
# =============================================

API_URL = "https://api.uptimerobot.com/v2/"
HEADERS = {"Content-Type": "application/x-www-form-urlencoded", "Cache-Control": "no-cache"}
BATCH_SIZE = 50  # Her sorguda çekilecek monitör sayısı (max 50)


def get_all_monitors():
    """Tüm monitörleri sayfalı şekilde çeker."""
    monitors = []
    offset = 0

    print("Monitörler çekiliyor...")

    while True:
        payload = {
            "api_key": API_KEY,
            "format": "json",
            "limit": BATCH_SIZE,
            "offset": offset,
        }

        response = requests.post(API_URL + "getMonitors", data=payload, headers=HEADERS)
        data = response.json()

        if data.get("stat") != "ok":
            print(f"HATA: Monitörler alınamadı -> {data}")
            sys.exit(1)

        batch = data["monitors"]
        monitors.extend(batch)
        total = data["pagination"]["total"]

        print(f"  {len(monitors)}/{total} monitör alındı...")

        if len(monitors) >= total:
            break

        offset += BATCH_SIZE
        time.sleep(0.5)  # Rate limit için bekleme

    return monitors


def update_monitor_timeout(monitor, timeout):
    """Tek bir monitörün timeout değerini günceller."""
    payload = {
        "api_key": API_KEY,
        "format": "json",
        "id": monitor["id"],
        "friendly_name": monitor["friendly_name"],
        "url": monitor["url"],
        "type": monitor["type"],
        "timeout": timeout,
    }

    response = requests.post(API_URL + "editMonitor", data=payload, headers=HEADERS)
    data = response.json()

    if data.get("stat") == "ok":
        return True, None
    else:
        return False, data.get("error", data)


def main():
    if API_KEY == "YOUR_API_KEY_HERE":
        print("HATA: Lütfen API_KEY değerini scriptte güncelleyin.")
        print("  UptimeRobot > My Settings > API Settings > Main API Key")
        sys.exit(1)

    monitors = get_all_monitors()
    print(f"\nToplam {len(monitors)} monitör bulundu.\n")

    if SKIP_FIRST > 0:
        print(f"İlk {SKIP_FIRST} monitör atlanıyor (zaten güncellendi)...")
        monitors = monitors[SKIP_FIRST:]
        print(f"Kalan {len(monitors)} monitör güncellenecek.\n")

    if DRY_RUN:
        print("=== DRY RUN MODU (gerçek güncelleme yapılmayacak) ===")
        print(f"Aşağıdaki {len(monitors)} monitörün timeout değeri {NEW_TIMEOUT}s olarak ayarlanacak:\n")
        for m in monitors:
            print(f"  [{m['id']}] {m['friendly_name']} - {m['url']}")
        print(f"\nGerçekten güncellemek için scriptte DRY_RUN = False yapın.")
        return

    print(f"=== GÜNCELLEME BAŞLIYOR (timeout = {NEW_TIMEOUT}s) ===\n")

    success_count = 0
    fail_count = 0
    failed_monitors = []

    for i, monitor in enumerate(monitors, SKIP_FIRST + 1):
        print(f"[{i}/{len(monitors)}] Güncelleniyor: {monitor['friendly_name']}", end=" ... ")

        ok, error = update_monitor_timeout(monitor, NEW_TIMEOUT)

        if ok:
            print("OK")
            success_count += 1
        else:
            print(f"HATA: {error}")
            fail_count += 1
            failed_monitors.append((monitor, error))

        # Rate limit: dakikada 10 istek sınırı için bekle
        time.sleep(6)

    print(f"\n{'='*50}")
    print(f"TAMAMLANDI: {success_count} başarılı, {fail_count} hatalı")

    if failed_monitors:
        print("\nHatalı monitörler:")
        for m, err in failed_monitors:
            print(f"  [{m['id']}] {m['friendly_name']} -> {err}")


if __name__ == "__main__":
    main()
