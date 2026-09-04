#!/usr/bin/env bash
set -euo pipefail

# 验证 COG Range、XYZ 瓦片、根/子 tileset 和 B3DM，不修改远端对象。

required=(
  HTTPS_BASE ORTHO_LAYER_ID TILES_LAYER_ID COG_PUBLIC_URL
  TEST_TILE_Z TEST_LONGITUDE TEST_LATITUDE
)
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    echo "缺少环境变量：${name}" >&2
    exit 2
  fi
done

work_dir="$(mktemp -d)"
trap 'rm -rf -- "${work_dir}"' EXIT

range_status="$(curl -sS -o "${work_dir}/range.bin" -w '%{http_code}' \
  -H 'Range: bytes=0-1023' "${COG_PUBLIC_URL}")"
if [[ "${range_status}" != "206" ]]; then
  echo "COG Range 验证失败，期望 206，实际 ${range_status}" >&2
  exit 3
fi
range_bytes="$(wc -c < "${work_dir}/range.bin" | tr -d ' ')"
if [[ "${range_bytes}" != "1024" ]]; then
  echo "COG Range 字节数错误：${range_bytes}" >&2
  exit 4
fi

read -r tile_x tile_y < <(python3 - "${TEST_TILE_Z}" "${TEST_LONGITUDE}" "${TEST_LATITUDE}" <<'PY'
import math
import sys
z = int(sys.argv[1])
lon = float(sys.argv[2])
lat = float(sys.argv[3])
x = int((lon + 180.0) / 360.0 * (1 << z))
y = int((1.0 - math.asinh(math.tan(math.radians(lat))) / math.pi) / 2.0 * (1 << z))
print(x, y)
PY
)

raster_url="${HTTPS_BASE%/}/gis/raster/${ORTHO_LAYER_ID}/${TEST_TILE_Z}/${tile_x}/${tile_y}.png"
raster_status="$(curl -sS -o "${work_dir}/tile.png" -w '%{http_code}' "${raster_url}")"
if [[ "${raster_status}" != "200" ]]; then
  echo "XYZ Tile 验证失败：${raster_url}，HTTP ${raster_status}" >&2
  exit 5
fi

root_url="${HTTPS_BASE%/}/gis/3d/${TILES_LAYER_ID}/tileset.json"
curl -fsS "${root_url}" -o "${work_dir}/tileset.json"
read -r child_uri b3dm_uri < <(python3 - "${work_dir}/tileset.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)

uris = []
def walk(node):
    content = node.get("content") or {}
    uri = content.get("uri") or content.get("url")
    if uri:
        uris.append(uri)
    for child in node.get("children") or []:
        walk(child)

walk(document["root"])
child = next((uri for uri in uris if uri.lower().endswith(".json")), "")
b3dm = next((uri for uri in uris if uri.lower().endswith(".b3dm")), "")
print(child, b3dm)
PY
)

if [[ -n "${child_uri}" ]]; then
  child_url="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urljoin(sys.argv[1], sys.argv[2]))' "${root_url}" "${child_uri}")"
  curl -fsS "${child_url}" -o "${work_dir}/child.json"
  if [[ -z "${b3dm_uri}" ]]; then
    b3dm_uri="$(python3 - "${work_dir}/child.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    document = json.load(stream)
uris = []
def walk(node):
    content = node.get("content") or {}
    uri = content.get("uri") or content.get("url")
    if uri:
        uris.append(uri)
    for child in node.get("children") or []:
        walk(child)
walk(document["root"])
print(next((uri for uri in uris if uri.lower().endswith(".b3dm")), ""))
PY
)"
  fi
  b3dm_base="${child_url}"
else
  b3dm_base="${root_url}"
fi

if [[ -z "${b3dm_uri}" ]]; then
  echo "未在根或首个子 tileset 中找到 B3DM URI" >&2
  exit 6
fi
b3dm_url="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.urljoin(sys.argv[1], sys.argv[2]))' "${b3dm_base}" "${b3dm_uri}")"
b3dm_status="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Range: bytes=0-27' "${b3dm_url}")"
if [[ "${b3dm_status}" != "200" && "${b3dm_status}" != "206" ]]; then
  echo "B3DM 验证失败：${b3dm_url}，HTTP ${b3dm_status}" >&2
  exit 7
fi

echo "COG Range：206，bytes=${range_bytes}"
echo "XYZ Tile：200，url=${raster_url}，bytes=$(wc -c < "${work_dir}/tile.png" | tr -d ' ')"
echo "3D Tiles 根：200，url=${root_url}"
[[ -n "${child_uri}" ]] && echo "3D Tiles 子层：200，uri=${child_uri}"
echo "B3DM：HTTP ${b3dm_status}，uri=${b3dm_uri}"
