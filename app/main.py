from fastapi import FastAPI
import os

app = FastAPI()

@app.get("/health")
def health():
    return {"ok": True}

@app.get("/secret")
def secret():
    return {"demo_secret_present": bool(os.getenv("DEMO_SECRET"))}