#!/usr/bin/env python3
"""
Sistem Bilgisi Scripti
CPU, Memory ve Disk kullanim bilgilerini gosterir
"""

import psutil

def get_system_info():
    cpu_usage = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')

    system_info = {
        "CPU Usage (%)": cpu_usage,
        "Total Memory (GB)": round(memory.total / (1024 ** 3), 2),
        "Used Memory (GB)": round(memory.used / (1024 ** 3), 2),
        "Memory Usage (%)": memory.percent,
        "Total Disk Space (GB)": round(disk.total / (1024 ** 3), 2),
        "Used Disk Space (GB)": round(disk.used / (1024 ** 3), 2),
        "Disk Usage (%)": disk.percent,
    }

    return system_info

if __name__ == "__main__":
    info = get_system_info()
    print(f"System Information: {info}")
