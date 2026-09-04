#!/usr/bin/env bash
set -euo pipefail

# 只读审计东明生产库中的 GIS 表与登记数据，不输出数据库凭据。

app_dir="${DONGMING_APP_DIR:-/opt/dongming}"
start_script="${app_dir}/startApp.sh"
current_jar="${app_dir}/dongming.jar"
database="${DONGMING_DATABASE:-smart_agriculture}"
mysql_args=(--batch --raw --skip-column-names --connect-timeout=5)

if mysql "${mysql_args[@]}" -e 'SELECT 1' >/dev/null 2>&1; then
  run_mysql() {
    mysql "${mysql_args[@]}" "${database}" "$@"
  }
else
  if [[ ! -r "${start_script}" ]]; then
    echo "无法读取 ${start_script}，且本机 socket 认证失败" >&2
    exit 2
  fi

  while IFS= read -r line; do
    case "${line}" in
      export\ DB_HOST=*|export\ DB_PORT=*|export\ DB_NAME=*|export\ DB_USER=*|export\ DB_PWD=*)
        eval "${line}"
        ;;
    esac
  done < "${start_script}"

  # 生产启动脚本只覆盖 DB_HOST 时，从当前运行 JAR 的配置占位符读取其默认值。
  jar_config="$(unzip -p "${current_jar}" BOOT-INF/classes/config/application-prod.yml)"
  if [[ -z "${DB_USER:-}" ]]; then
    DB_USER="$(printf '%s\n' "${jar_config}" | sed -nE 's/^[[:space:]]*username:[[:space:]]*\$\{DB_USER:([^}]*)\}[[:space:]]*$/\1/p' | head -n 1)"
  fi
  if [[ -z "${DB_PWD:-}" ]]; then
    DB_PWD="$(printf '%s\n' "${jar_config}" | sed -nE 's/^[[:space:]]*password:[[:space:]]*\$\{DB_PWD:([^}]*)\}[[:space:]]*$/\1/p' | head -n 1)"
  fi
  unset jar_config

  : "${DB_HOST:?startApp.sh 缺少 DB_HOST}"
  : "${DB_USER:?startApp.sh 缺少 DB_USER}"
  : "${DB_PWD:?startApp.sh 缺少 DB_PWD}"
  database="${DB_NAME:-smart_agriculture}"
  db_port="${DB_PORT:-3306}"
  run_mysql() {
    MYSQL_PWD="${DB_PWD}" mysql "${mysql_args[@]}" \
      --host "${DB_HOST}" --port "${db_port}" --user "${DB_USER}" \
      "${database}" "$@"
  }
fi

echo "database=${database}"
echo "existing_project_or_tenant_columns:"
run_mysql -e "
SELECT TABLE_NAME, COLUMN_NAME
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND COLUMN_NAME IN ('project_id', 'tenant_id')
ORDER BY TABLE_NAME, COLUMN_NAME;
"
run_mysql -e "
SELECT TABLE_NAME
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME LIKE 'gis\\_%'
ORDER BY TABLE_NAME;
"

for table in gis_dataset gis_processing_task gis_artifact gis_layer; do
  exists="$(run_mysql -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='${table}'")"
  if [[ "${exists}" == "1" ]]; then
    count="$(run_mysql -e "SELECT COUNT(*) FROM ${table}")"
    echo "${table}_count=${count}"
  else
    echo "${table}_count=<absent>"
  fi
done

dataset_exists="$(run_mysql -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='gis_dataset'")"
if [[ "${dataset_exists}" == "1" ]]; then
  echo "gis_dataset_rows:"
  run_mysql -e "
  SELECT id, tenant_id, project_id, name, dataset_type, source_format, status,
         source_bucket, source_object_key, source_size, crs
  FROM gis_dataset
  ORDER BY id
  LIMIT 100;
  "
fi

artifact_exists="$(run_mysql -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='gis_artifact'")"
if [[ "${artifact_exists}" == "1" ]]; then
  echo "gis_artifact_rows:"
  run_mysql -e "
  SELECT id, tenant_id, project_id, dataset_id, task_id, artifact_type, status,
         bucket, object_key, entry_object_key, size_bytes
  FROM gis_artifact
  ORDER BY id
  LIMIT 100;
  "
fi

layer_exists="$(run_mysql -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='gis_layer'")"
if [[ "${layer_exists}" == "1" ]]; then
  echo "gis_layer_rows:"
  run_mysql -e "
  SELECT id, tenant_id, project_id, dataset_id, artifact_id, name, layer_type,
         status, service_url
  FROM gis_layer
  ORDER BY id
  LIMIT 100;
  "
fi
