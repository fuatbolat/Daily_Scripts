#!/usr/bin/env python3
"""
Basit FastAPI Uygulamasi
Ornek REST API endpoint'i

Calistirmak icin:
    uvicorn basic_fastapi_app:app --reload
"""

from fastapi import FastAPI

app = FastAPI()


BOOKS = [
        {"title": "1984", "author": "George Orwell"},
        {"title": "Brave New World", "author": "Aldous Huxley"},
        {"title": "Fahrenheit 451", "author": "Ray Bradbury"},
]   


@app.get("/main/{title}")
def main(title):
    for book in BOOKS:
        if book["title"].lower() == title.lower():
            return book
    return {"error": "Book not found"}

@app.get("/main/author/")
def main(author:str):
    for book in BOOKS:
        if book["author"].lower() == author.lower():
            return book
    return {"error": "Book not found"}

@app.on_event("startup")
def start():
    print("starting your app")

@app.on_event("shutdown")
def shutdown():
    print("closing your app")
    