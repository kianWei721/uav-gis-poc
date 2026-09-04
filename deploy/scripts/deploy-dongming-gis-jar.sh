#!/usr/bin/env bash
set -euo pipefail

# 以可回滚方式部署仅叠加 GIS 文件的生产 Jar。
app_dir="${DONGMING_APP_DIR:-/opt/dongming}"
current_jar="${app_dir}/dongming.jar"
staging_jar="${app_dir}/dongming.jar.gis-overlay"
expected_current_sha="${EXPECTED_CURRENT_JAR_SHA256:-}"
expected_staging_sha="${EXPECTED_STAGING_JAR_SHA256:-}"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_dir="${app_dir}/backups/gis-${timestamp}"
backup_jar="${backup_dir}/dongming.jar"
process_pattern='^java -Dspring.profiles.active=prod -jar dongming.jar -Xms256m -Xmx512m$'
rollback_needed=0

sha256() {
  sha256sum "$1" | awk '{print $1}'
}

wait_stopped() {
  target_pid="$1"
  for _ in $(seq 1 45); do
    if ! kill -0 "${target_pid}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_started() {
  for _ in $(seq 1 90); do
    new_pid="$(pgrep -f "${process_pattern}" || true)"
    if [[ -n "${new_pid}" ]] && ss -lnt | awk '{print $4}' | grep -qE '(^|:)10522$'; then
      if grep -q 'Started AppRun' "${app_dir}/local.log" 2>/dev/null; then
        return 0
      fi
    fi
    sleep 1
  done
  return 1
}

start_app() {
  (
    cd "${app_dir}"
    bash ./startApp.sh
  )
}

rollback_on_error() {
  code=$?
  if [[ "${rollback_needed}" -eq 1 ]]; then
    echo "新版 Backend 启动失败，正在恢复旧 Jar" >&2
    failed_pid="$(pgrep -f "${process_pattern}" || true)"
    if [[ -n "${failed_pid}" ]]; then
      kill -TERM ${failed_pid} 2>/dev/null || true
      wait_stopped "${failed_pid}" || kill -KILL ${failed_pid} 2>/dev/null || true
    fi
    cp -p "${backup_jar}" "${current_jar}.rollback"
    mv -f "${current_jar}.rollback" "${current_jar}"
    start_app
    wait_started || true
    echo "旧 Jar 已恢复：${backup_jar}" >&2
  fi
  exit "${code}"
}
trap rollback_on_error ERR

if [[ "$(id -u)" -ne 0 ]]; then
  echo "必须以 root 执行" >&2
  exit 2
fi
if [[ -z "${expected_current_sha}" || -z "${expected_staging_sha}" ]]; then
  echo "缺少 EXPECTED_CURRENT_JAR_SHA256 或 EXPECTED_STAGING_JAR_SHA256" >&2
  exit 2
fi
if [[ "$(sha256 "${current_jar}")" != "${expected_current_sha}" ]]; then
  echo "当前生产 Jar 哈希已变化，拒绝部署" >&2
  exit 3
fi
if [[ "$(sha256 "${staging_jar}")" != "${expected_staging_sha}" ]]; then
  echo "GIS staging Jar 哈希不匹配，拒绝部署" >&2
  exit 4
fi

old_pid="$(pgrep -f "${process_pattern}" || true)"
if [[ -z "${old_pid}" || "$(printf '%s\n' ${old_pid} | wc -l)" -ne 1 ]]; then
  echo "生产 Java 进程数量不是 1，拒绝部署" >&2
  exit 5
fi

mkdir -p "${backup_dir}"
cp -p "${current_jar}" "${backup_jar}"
cp -p "${app_dir}/startApp.sh" "${backup_dir}/startApp.sh"
if [[ -f "${app_dir}/local.log" ]]; then
  mv "${app_dir}/local.log" "${backup_dir}/local.log.before-deploy"
fi

kill -TERM "${old_pid}"
if ! wait_stopped "${old_pid}"; then
  echo "旧 Java 进程未在 45 秒内停止，拒绝替换 Jar" >&2
  exit 6
fi

rollback_needed=1
cp -p "${staging_jar}" "${current_jar}.new"
mv -f "${current_jar}.new" "${current_jar}"
start_app
wait_started

if grep -E 'APPLICATION FAILED TO START|Exception encountered during context initialization' \
     "${app_dir}/local.log" >/dev/null 2>&1; then
  echo "启动日志出现致命错误" >&2
  exit 7
fi

health_code="$(curl --silent --output /dev/null --write-out '%{http_code}' \
  http://127.0.0.1:10522/api/internal/gis-worker/health)"
if [[ "${health_code}" != "401" ]]; then
  echo "Internal API 未按空 Token 返回 401：http=${health_code}" >&2
  exit 8
fi

rollback_needed=0
trap - ERR
echo "backend_deploy=OK"
echo "backup_dir=${backup_dir}"
echo "new_pid=$(pgrep -f "${process_pattern}")"
echo "jar_sha256=$(sha256 "${current_jar}")"
echo "internal_health_without_token=${health_code}"
