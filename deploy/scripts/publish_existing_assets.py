#!/usr/bin/env python3
"""将已验证的 COG 和 3D Tiles 幂等发布到 MinIO。"""

import json
import mimetypes
import os
import sys
from pathlib import Path
from typing import Dict, Iterable, Tuple

from minio import Minio
from minio.error import S3Error


BUCKET = "gis-published"
POLICY_SID = "DongmingFormalGisReadOnly"


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"缺少环境变量：{name}")
    return value


def content_type(path: Path) -> str:
    suffix = path.suffix.lower()
    overrides = {
        ".json": "application/json",
        ".b3dm": "application/octet-stream",
        ".cmpt": "application/octet-stream",
        ".glb": "model/gltf-binary",
        ".gltf": "model/gltf+json",
        ".tif": "image/tiff",
        ".tiff": "image/tiff",
    }
    return overrides.get(suffix) or mimetypes.guess_type(path.name)[0] or "application/octet-stream"


def local_tiles(root: Path) -> Iterable[Tuple[Path, str]]:
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        yield path, path.relative_to(root).as_posix()


def put_if_needed(client: Minio, source: Path, object_name: str) -> str:
    size = source.stat().st_size
    try:
        remote = client.stat_object(BUCKET, object_name)
    except S3Error as exc:
        if exc.code not in {"NoSuchKey", "NoSuchObject", "NotFound"}:
            raise
    else:
        if remote.size != size:
            raise RuntimeError(
                f"目标对象已存在且大小不同，拒绝覆盖：{BUCKET}/{object_name} "
                f"local={size} remote={remote.size}"
            )
        return "skipped"

    client.fput_object(
        BUCKET,
        object_name,
        str(source),
        content_type=content_type(source),
    )
    remote = client.stat_object(BUCKET, object_name)
    if remote.size != size:
        raise RuntimeError(
            f"上传后大小不一致：{BUCKET}/{object_name} local={size} remote={remote.size}"
        )
    return "uploaded"


def ensure_read_policy(client: Minio, prefixes: Iterable[str]) -> None:
    resources = [f"arn:aws:s3:::{BUCKET}/{prefix}/*" for prefix in prefixes]
    statement: Dict[str, object] = {
        "Sid": POLICY_SID,
        "Effect": "Allow",
        "Principal": {"AWS": ["*"]},
        "Action": ["s3:GetObject"],
        "Resource": resources,
    }
    try:
        current = json.loads(client.get_bucket_policy(BUCKET))
    except S3Error as exc:
        if exc.code not in {"NoSuchBucketPolicy", "NoSuchPolicy", "PolicyNotFound"}:
            raise
        current = {"Version": "2012-10-17", "Statement": []}

    statements = current.setdefault("Statement", [])
    if not isinstance(statements, list):
        raise RuntimeError("现有 Bucket Policy 的 Statement 不是数组，拒绝覆盖")
    current["Statement"] = [item for item in statements if item.get("Sid") != POLICY_SID]
    current["Statement"].append(statement)
    client.set_bucket_policy(BUCKET, json.dumps(current, separators=(",", ":")))


def remote_stats(client: Minio, prefix: str) -> Tuple[int, int]:
    count = 0
    size = 0
    for item in client.list_objects(BUCKET, prefix=prefix + "/", recursive=True):
        count += 1
        size += item.size
    return count, size


def main() -> int:
    project_id = required("PROJECT_ID")
    ortho_dataset_id = required("ORTHO_DATASET_ID")
    ortho_artifact_id = required("ORTHO_ARTIFACT_ID")
    tiles_dataset_id = required("TILES_DATASET_ID")
    tiles_artifact_id = required("TILES_ARTIFACT_ID")
    cog_source = Path(required("COG_SOURCE"))
    tiles_source = Path(required("TILES_SOURCE"))

    if not cog_source.is_file():
        raise RuntimeError(f"COG 文件不存在：{cog_source}")
    if not (tiles_source / "tileset.json").is_file() or not (tiles_source / "Data").is_dir():
        raise RuntimeError(f"3D Tiles 必须同时包含 tileset.json 和 Data 目录：{tiles_source}")

    client = Minio(
        required("MINIO_S3_ENDPOINT"),
        access_key=required("MINIO_ACCESS_KEY"),
        secret_key=required("MINIO_SECRET_KEY"),
        secure=False,
        region=os.environ.get("MINIO_REGION", "us-east-1"),
    )
    if not client.bucket_exists(BUCKET):
        client.make_bucket(BUCKET, location=os.environ.get("MINIO_REGION", "us-east-1"))
        print(f"已创建 Bucket：{BUCKET}")

    cog_prefix = f"{project_id}/{ortho_dataset_id}/{ortho_artifact_id}/ortho"
    cog_key = f"{cog_prefix}/result.cog.tif"
    tiles_prefix = f"{project_id}/{tiles_dataset_id}/{tiles_artifact_id}/3dtiles"

    print(f"COG {put_if_needed(client, cog_source, cog_key)}：{BUCKET}/{cog_key}")

    local_count = 0
    local_size = 0
    uploaded = 0
    skipped = 0
    for path, relative_name in local_tiles(tiles_source):
        local_count += 1
        local_size += path.stat().st_size
        result = put_if_needed(client, path, f"{tiles_prefix}/{relative_name}")
        if result == "uploaded":
            uploaded += 1
        else:
            skipped += 1
        if local_count % 100 == 0:
            print(f"3D Tiles 进度：checked={local_count}, uploaded={uploaded}, skipped={skipped}")

    remote_count, remote_size = remote_stats(client, tiles_prefix)
    if (local_count, local_size) != (remote_count, remote_size):
        raise RuntimeError(
            "3D Tiles 校验失败："
            f"local=({local_count},{local_size}) remote=({remote_count},{remote_size})"
        )

    ensure_read_policy(client, [cog_prefix, tiles_prefix])
    print(f"3D Tiles 发布完成：files={remote_count}, bytes={remote_size}")
    print("MinIO 精确只读策略已更新，不影响 Bucket 中其他前缀")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, S3Error, OSError, ValueError) as exc:
        print(f"正式成果发布失败：{exc}", file=sys.stderr)
        sys.exit(1)
