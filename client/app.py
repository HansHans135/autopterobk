import tarfile
import os
import json
import fnmatch
import requests
from types import SimpleNamespace

app_path = os.path.dirname(__file__)
with open(f"{app_path}/config.json") as f:
    config = SimpleNamespace(**json.load(f))
config.base_url = (
    config.base_url if config.base_url.endswith("/") else config.base_url + "/"
)


def compression(dir_path, file_name, exclude_patterns):
    def should_exclude(tarinfo):
        """glob filter"""
        normalized_path = tarinfo.name.replace("\\", "/").lstrip("./")

        for pattern in exclude_patterns:
            if pattern.endswith("/"):
                dir_pattern = pattern.rstrip("/")
                if normalized_path == dir_pattern or normalized_path.startswith(
                    dir_pattern + "/"
                ):
                    print(f"! {tarinfo.name}")
                    return None
            else:
                if fnmatch.fnmatch(os.path.basename(normalized_path), pattern):
                    print(f"! {tarinfo.name}")
                    return None
                if fnmatch.fnmatch(normalized_path, pattern):
                    print(f"! {tarinfo.name}")
                    return None

        return tarinfo

    with tarfile.open(file_name, "w:gz") as tar:
        tar.add(dir_path, arcname=os.path.basename(dir_path), filter=should_exclude)

    print(f"Successfully created archive {file_name} from {dir_path}")


def upload_file(file_path):
    try:
        with open(file_path, 'rb') as f:
            files = {'file': f}
            data = {'api_key': config.api_key}
            response = requests.post(f"{config.base_url}uploader", files=files, data=data)

        if response.status_code == 200:
            os.remove(file_path)
        else:
            print(f"error: {file_path}, code: {response.status_code}")
    except Exception as e:
        print(f"error: {e}")


r = requests.get(f"{config.base_url}api/list")
data_path = requests.get(f"{config.base_url}api/path").text
data = r.json()
for i in data:
    if os.path.isdir(f"{data_path}/{i}"):
        tar_filename = f"{i}.tar.gz"
        compression(f"{data_path}/{i}", tar_filename, data[i])
        upload_file(tar_filename)
