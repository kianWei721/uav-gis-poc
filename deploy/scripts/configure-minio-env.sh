#!/usr/bin/env bash
set -euo pipefail

# 在发布服务器终端交互录入 MinIO 凭据，输入内容不回显，也不经过聊天或命令行参数。

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output="${1:-${script_dir}/../titiler/.env}"

if [[ -e "${output}" ]]; then
  echo "目标文件已存在，拒绝覆盖：${output}" >&2
  exit 2
fi

read -r -p "MinIO Access Key: " access_key
read -r -s -p "MinIO Secret Key: " secret_key
printf '\n'
read -r -p "MinIO URL（例如 http://minio:9000）: " minio_url
read -r -p "MinIO S3 Endpoint（例如 minio:9000）: " minio_endpoint

if [[ -z "${access_key}" || -z "${secret_key}" || -z "${minio_url}" || -z "${minio_endpoint}" ]]; then
  unset access_key secret_key minio_url minio_endpoint
  echo "MinIO 凭据和地址不能为空" >&2
  exit 3
fi

umask 077
tmp_file="$(mktemp "${output}.XXXXXX")"
trap 'rm -f "${tmp_file}"' EXIT
{
  printf 'MINIO_URL=%q\n' "${minio_url}"
  printf 'MINIO_ACCESS_KEY=%q\n' "${access_key}"
  printf 'MINIO_SECRET_KEY=%q\n' "${secret_key}"
  printf 'MINIO_REGION=%q\n' 'us-east-1'
  printf 'MINIO_S3_ENDPOINT=%q\n' "${minio_endpoint}"
} > "${tmp_file}"
chmod 0600 "${tmp_file}"
mv "${tmp_file}" "${output}"
trap - EXIT
unset access_key secret_key minio_url minio_endpoint

echo "MinIO 环境文件已创建：${output}"
