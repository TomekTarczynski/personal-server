import argparse
import os
import posixpath

import dropbox
import dropbox_get_client

MAX_SIMPLE_UPLOAD = 150 * 1024 * 1024

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Upload a file to dropbox")
    parser.add_argument("--source-filename", type=str, required=True, help="Name of the file to be uploaded.")
    parser.add_argument("--source-folder", type=str, required=True, help="Folder with the source file.")
    parser.add_argument("--destination-filename", type=str, required=True, help="The name of the file that will be stored on dropbox.")
    parser.add_argument("--destination-folder", type=str, required=True, help="The dropbox folder to which file will be uploaded.")

    args = parser.parse_args()

    source_full_path = os.path.join(args.source_folder, args.source_filename)
    destination_full_path = posixpath.join(args.destination_folder, args.destination_filename)
    file_size = os.path.getsize(source_full_path)
    if file_size > MAX_SIMPLE_UPLOAD:
        raise RuntimeError("File too large for simple upload. Use upload sessions.")

    dbx = dropbox_get_client.get_client()

    with open(source_full_path, "rb") as f:
        dbx.files_upload(
            f.read(),
            destination_full_path,
            mode=dropbox.files.WriteMode.overwrite
        )
