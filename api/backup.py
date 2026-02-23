import argparse
import os
import posixpath
import tarfile

from datetime import datetime

import dropbox
from fastapi import FastAPI, HTTPException, APIRouter

router = APIRouter(prefix="/backup", tags=["backup"])

MAX_SIMPLE_UPLOAD = 150 * 1024 * 1024

async def startup() -> None:
    pass

def get_client() -> dropbox.Dropbox:
    return dropbox.Dropbox(
        app_key=os.environ["DROPBOX_APP_KEY"],
        app_secret=os.environ["DROPBOX_APP_SECRET"],
        oauth2_refresh_token=os.environ["DROPBOX_REFRESH_TOKEN"],
    )


def upload_file(source_path: str, destination_path) -> None:
    file_size = os.path.getsize(source_path)

    if file_size > MAX_SIMPLE_UPLOAD:
        raise RuntimeError("File too large for simple upload. Use upload sessions.")
    
    dbx = get_client()

    with open(source_path, "rb") as f:
        dbx.files_upload(
            f.read(),
            destination_path,
            mode=dropbox.files.WriteMode.overwrite
        )

def pack_data_folder():
    data_folder = os.environ["DATA_FOLDER"]
    backup_folder = os.environ["BACKUP_FOLDER"]
    ts = datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
    backup_filename = f"DATA-{ts}.tar.gz"
    backup_path = os.path.join(backup_folder, backup_filename)

    os.makedirs(backup_folder, exist_ok=True)

    with tarfile.open(backup_path, "w:gz") as tar:
        tar.add(data_folder, arcname=".")

    return {"backup_path": backup_path, "backup_filename": backup_filename}

@router.post("/backup")
def backup():
    backup_dict = pack_data_folder()
    backup_path = backup_dict["backup_path"]
    backup_filename = backup_dict["backup_filename"]
    dropbox_folder= os.environ["DROPBOX_FOLDER"]
    dropbox_path = posixpath.join(dropbox_folder, backup_filename)

    upload_file(backup_path, dropbox_path)
    return {"ok": True, "message": "Backup completed", "dropbox_path": dropbox_path}

@router.get("/list")
def list_backup_files():
    dbx = get_client()
    dropbox_folder= os.environ["DROPBOX_FOLDER"]
    result = dbx.files_list_folder(dropbox_folder)

    return {
        "entries": [
            {
                "name": e.name,
                "path": e.path_display,
                "size": getattr(e, "size", None)
            }
            for e in result.entries
        ]
    }