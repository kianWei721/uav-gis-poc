#!/usr/bin/env bash
set -euo pipefail

# 精确删除本次部署临时公钥，保留 authorized_keys 中其他条目和权限。
authorized_keys="${1:?必须提供 authorized_keys 的绝对路径}"
key_tag="codex-gis-worker-106-temporary"

if [[ ! -f "${authorized_keys}" ]]; then
  echo "authorized_keys 不存在：${authorized_keys}" >&2
  exit 2
fi
count="$(grep -cF "${key_tag}" "${authorized_keys}" || true)"
if [[ "${count}" -ne 1 ]]; then
  echo "临时公钥数量不是 1，拒绝修改：count=${count}" >&2
  exit 3
fi

temp_file="$(mktemp "${authorized_keys}.XXXXXX")"
trap 'rm -f "${temp_file}"' EXIT
grep -vF "${key_tag}" "${authorized_keys}" >"${temp_file}" || true
chown --reference="${authorized_keys}" "${temp_file}"
chmod --reference="${authorized_keys}" "${temp_file}"
mv "${temp_file}" "${authorized_keys}"
trap - EXIT
echo "temporary_ssh_key_removed=1"
