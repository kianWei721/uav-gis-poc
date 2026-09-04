#!/usr/bin/env bash
set -euo pipefail

# 以生产 Jar 为基线，仅叠加已编译的 GIS class 和 Mapper XML。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="${DONGMING_APP_DIR:-/opt/dongming}"
old_jar="${1:-${app_dir}/dongming.jar}"
gis_jar="${2:-${app_dir}/dongming.jar.gis-staging}"
output_jar="${3:-${app_dir}/dongming.jar.gis-overlay}"
compare_script="${4:-${script_dir}/compare_gis_deployment_jars.py}"
overlay_script="${5:-${script_dir}/overlay_gis_jar.py}"

if [[ ! -f "${old_jar}" || ! -f "${gis_jar}" || ! -f "${compare_script}" ||
      ! -f "${overlay_script}" ]]; then
  echo "缺少生产 Jar、GIS staging Jar、叠加脚本或比较脚本" >&2
  exit 2
fi
if [[ -e "${output_jar}" ]]; then
  echo "输出文件已经存在，拒绝覆盖：${output_jar}" >&2
  exit 3
fi

python "${overlay_script}" "${old_jar}" "${gis_jar}" "${output_jar}"
chown root:root "${output_jar}"
chmod 0644 "${output_jar}"

python "${compare_script}" "${old_jar}" "${output_jar}"
sha256sum "${output_jar}"
