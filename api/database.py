import json
import os
import sqlite3
import asyncio

from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException, APIRouter
from pydantic import BaseModel

router = APIRouter(prefix="/kv", tags=["kv"])

DB_PATH = os.environ.get("DB_PATH", "/data/sqlite.db")

class KVPut(BaseModel):
    value: dict

def connect():
    con = sqlite3.connect(DB_PATH)
    return con

async def startup() -> None:
    with connect() as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS kv (
                k TEXT PRIMARY KEY,
                v TEXT NOT NULL,
                updated_at TEXT NOT NULL )
        """)

@router.put("/{key}")
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

@router.get("/{key}")
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

@router.get("")
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

@router.delete("/{key}")
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