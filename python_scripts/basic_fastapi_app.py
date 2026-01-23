#!/usr/bin/env python3
"""
Basit FastAPI Uygulamasi
Ornek REST API endpoint'i

Calistirmak icin:
    uvicorn basic_fastapi_app:app --reload
"""

from fastapi import FastAPI

app = FastAPI()


@app.get("/main/{name}")
def main(name):
    return {"Selam": name}
