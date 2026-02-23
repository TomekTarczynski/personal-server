import json
import os
import sqlite3
import asyncio

from datetime import datetime, timezone
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

import backup as b

from database import router as db_router, startup as db_startup
from backup import router as backup_router, startup as backup_startup


app = FastAPI()
app.include_router(db_router)
app.include_router(backup_router)

@app.on_event("startup")
async def startup() -> None:
    await db_startup()
    await backup_startup()

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", "8000"))
    uvicorn.run("main:app", host="0.0.0.0", port=port)
