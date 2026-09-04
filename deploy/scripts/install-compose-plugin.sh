#!/usr/bin/env bash
set -euo pipefail

# 106 未预装 Docker Compose，本脚本只在当前用户目录安装固定版本插件。

version="v5.5.0"
expected_sha256="c57ab918abd5b05ca7e7d0f275875dd1330a695074f309dc9eab1b49efafcd4b"
plugin_dir="${HOME}/.docker/cli-plugins"
plugin_path="${plugin_dir}/docker-compose"
download_url="https://github.com/docker/compose/releases/download/${version}/docker-compose-linux-x86_64"

mkdir -p "${plugin_dir}"

if [[ -f "${plugin_path}" ]]; then
  installed_sha256="$(sha256sum "${plugin_path}" | awk '{print $1}')"
  if [[ "${installed_sha256}" == "${expected_sha256}" ]]; then
    chmod 0755 "${plugin_path}"
    docker compose version
    exit 0
  fi

  echo "已有 Compose 插件与固定版本不一致，拒绝覆盖：${plugin_path}" >&2
  exit 3
fi

tmp_path="$(mktemp "${plugin_dir}/docker-compose.XXXXXX")"
trap 'rm -f "${tmp_path}"' EXIT

curl --fail --location --silent --show-error "${download_url}" --output "${tmp_path}"
actual_sha256="$(sha256sum "${tmp_path}" | awk '{print $1}')"
if [[ "${actual_sha256}" != "${expected_sha256}" ]]; then
  echo "Docker Compose SHA-256 校验失败" >&2
  exit 4
fi

chmod 0755 "${tmp_path}"
mv "${tmp_path}" "${plugin_path}"
trap - EXIT

docker compose version
