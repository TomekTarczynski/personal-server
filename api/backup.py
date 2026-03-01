import os
from pathlib import Path
import posixpath
import tarfile
import shutil

from datetime import datetime

import dropbox
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

class DownloadRequest(BaseModel):
    dropbox_path: str
    local_path: str

class RestoreRequest(BaseModel):
    local_path: str

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


@router.post("/download")
def download_file(req: DownloadRequest) -> dict:
    dbx = get_client()

    local_path = Path(req.local_path)

    dbx.files_download_to_file(download_path=str(local_path), path=req.dropbox_path)

    return {"ok": True, "dropbox_path": req.dropbox_path, "local_path": str(local_path)}

def _clear_directory_contents(dir_path: Path) -> None:
    if not dir_path.exists():
        dir_path.mkdir(parents=True, exist_ok=True)
        return
    
    for child in dir_path.iterdir():
        if child.is_dir() and not child.is_symlink():
            shutil.rmtree(child)
        else:
            child.unlink(missing_ok=True)

def restore_data_folder_from_tar(local_tar_path: str) -> dict:
    data_folder = Path(os.environ["DATA_FOLDER"]).resolve()
    tar_path = Path(local_tar_path).expanduser().resolve()

    try:
        with tarfile.open(tar_path, "r:gz") as tar:
            members = tar.getmembers()

            _clear_directory_contents(data_folder)

            tar.extractall(path=str(data_folder), members=members)
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Restore failed: {type(e).__name__}: {e}")
    
    return {
        "ok": True,
        "message": "Restore completed",
        "restored_from": str(tar_path),
        "data_folder": str(data_folder)
    }


@router.post("/restore")
def restore_backup(req: RestoreRequest) -> dict:
    return restore_data_folder_from_tar(req.local_path)