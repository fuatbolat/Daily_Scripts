#!/usr/bin/env python3
"""
Health Check Scripti
URL'lerin erisilebilirligini kontrol eder
"""

import requests


def health_check(url):
    try:
        response = requests.get(url, timeout=5)
        return response.status_code == 200
    except requests.RequestException:
        return False

if __name__ == "__main__":
    url = input("Enter the URL to perform health check: ")
    if health_check(url):
        print(f"Health check passed for {url}")
    else:
        print(f"Health check failed for {url}")
