#!/usr/bin/env python3
"""只读检查 MinIO 认证、Bucket 和正式发布前缀。"""

import os
import sys

from minio import Minio
from minio.error import S3Error


def required(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        raise RuntimeError(f"缺少环境变量：{name}")
    return value


def main() -> int:
    client = Minio(
        required("MINIO_S3_ENDPOINT"),
        access_key=required("MINIO_ACCESS_KEY"),
        secret_key=required("MINIO_SECRET_KEY"),
        secure=False,
        region=os.environ.get("MINIO_REGION", "us-east-1"),
    )
    buckets = sorted(bucket.name for bucket in client.list_buckets())
    print("minio_auth=OK")
    print("buckets=" + (",".join(buckets) if buckets else "<empty>"))
    if "gis-published" in buckets:
        objects = client.list_objects("gis-published", recursive=True)
        first = next(objects, None)
        print("gis_published=" + ("non_empty" if first else "empty"))
    else:
        print("gis_published=absent")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, S3Error) as exc:
        print(f"MinIO 检查失败：{exc}", file=sys.stderr)
        sys.exit(1)
