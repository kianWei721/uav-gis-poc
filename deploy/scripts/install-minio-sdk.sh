#!/usr/bin/env bash
set -euo pipefail

# 使用已校验的离线 wheel，在部署目录创建独立 MinIO SDK 环境。

deploy_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
venv_dir="${deploy_dir}/.venv"
vendor_dir="${deploy_dir}/vendor"
lock_file="${deploy_dir}/minio/requirements.lock"

if [[ -e "${venv_dir}" ]]; then
  echo "虚拟环境已存在，拒绝自动覆盖：${venv_dir}" >&2
  exit 2
fi
if [[ ! -d "${vendor_dir}" || ! -f "${lock_file}" ]]; then
  echo "缺少离线 wheel 或锁文件" >&2
  exit 3
fi

python3 -m venv "${venv_dir}"
"${venv_dir}/bin/python" -m pip install \
  --no-index \
  --find-links "${vendor_dir}" \
  --require-hashes \
  --requirement "${lock_file}"

"${venv_dir}/bin/python" -c "import minio; print('minio-sdk=' + minio.__version__)"
