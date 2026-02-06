import json
import os
import sqlite3

from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

DB_PATH = os.environ.get("DB_PATH", "/data/sqlite.db")

def connect():
    con = sqlite3.connect(DB_PATH)
    return con

app = FastAPI()

class KVPut(BaseModel):
    value: dict


@app.on_event("startup")
def startup() -> None:
    with connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS kv (
                k TEXT PRIMARY KEY,
                v TEXT NOT NULL,
                updated_at TEXT NOT NULL )
        """)

@app.get("/healthz")
def healthz():
    return {"status": "ok"}

@app.get("/hello")
def hello():
    return {"message": "hello from fastapi"}

@app.put("/kv/{key}")
def put_kv(key: str, body: KVPut):
    v_json = json.dumps(body.value, separators=(",", ":"), ensure_ascii=False)
    now = datetime.now(timezone.utc).isoformat()

    con = connect()
    try:
        con.execute(
            """
            INSERT INTO kv(k, v, updated_at) VALUES (?, ?, ?)
            ON CONFLICT(k) DO UPDATE SET
                v = excluded.v,
                updated_at = excluded.updated_at
            """,
            (key, v_json, now)
        )
        con.commit()
        return {"key": key, "updated_at": now, "upserted": True}
    finally:
        con.close()

@app.get("/kv/{key}")
def get_kv(key: str):
    con = connect()
    try:
        row = con.execute("SELECT v, updated_at FROM kv WHERE k = ?", (key,)).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Key not found")
        v_json, updated_at = row
        return {"key": key, "value": json.loads(v_json), "updated_at": updated_at}
    finally:
        con.close()

@app.get("/kv")
def list_keys():
    con = connect()
    try:
        rows = con.execute("SELECT k, updated_at FROM kv ORDER BY k").fetchall()

        return {
            "count": len(rows),
            "items": [{"key": k, "updated_at": updated_at} for (k, updated_at) in rows]
        }
    finally:
        con.close()

@app.delete("/kv/{key}")
def delete_kv(key: str):
    con = connect()
    try:
        cur = con.execute("DELETE FROM kv WHERE k = ?", (key,))
        con.commit()
        if cur.rowcount == 0:
            raise HTTPException(status_code=404, detail="key not found")
        return {"key": key, "deleted": True}
    finally:
        con.close()

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port)
