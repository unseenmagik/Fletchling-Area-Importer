#!/bin/bash
set -euo pipefail

# Load config.ini
config_file="config.ini"
if [[ ! -f "$config_file" ]]; then
  echo "❌ Config file '$config_file' not found!"
  exit 1
fi

declare -A config
while IFS='=' read -r raw_key raw_value; do
  key="$(echo "$raw_key" | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
  value="$(echo "$raw_value" | sed -E 's/^[[:space:]]+|[[:space:]]+$//')"
  # Skip blank lines, comments, or section headers
  [[ -z "$key" ]] && continue
  [[ "$key" =~ ^# ]] && continue
  [[ "$key" =~ ^\[.*\]$ ]] && continue
  config["$key"]="$value"
done < "$config_file"

# Assign config values
koji_url="${config[koji_url]:-}"
koji_token="${config[koji_token]:-}"
fletchling_reload_url="${config[fletchling_reload_url]:-}"
sleep_time_seconds="${config[sleep_time_seconds]:-60}"
enable_logs="${config[enable_logs]:-yes}"
retry_count="${config[retry_count]:-2}"
parallel_jobs="${config[parallel_jobs]:-1}"
importer_path="${config[importer_path]:-./fletchling-osm-importer}"
fletchling_config_dir="${config[fletchling_config_dir]:-./configs}"

# Defaults for CLI flags
area=""
run_immediately=false
enable_retry=false
enable_parallel=false
dry_run=false
clear_log=false

# Help output
print_help() {
  cat <<EOF
Usage: $0 [OPTIONS]
  -a          Import only a specific area
  -i          Run the script after generation
  -r          Enable retry
  -p          Enable parallel import
  -d          Dry-run
  -cl         Clear log before starting
  -h, --help  Show help
EOF
}

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a) shift; [[ $# -gt 0 ]] && area="$1" || { echo "❌ -a needs argument"; exit 1; } ;;
    -i) run_immediately=true ;;
    -r) enable_retry=true ;;
    -p) enable_parallel=true ;;
    -d) dry_run=true ;;
    -cl) clear_log=true ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "❌ Unknown option: $1"; print_help; exit 1 ;;
  esac
  shift
done

# Logging
echo "[$(date)] Starting import script generation..."
log_file="import-areas.log"
[[ "$clear_log" == true && -f "$log_file" ]] && echo "[$(date)] Clearing log file..." && > "$log_file"

echo "[$(date)] Fetching area list from API..."
response=$(curl -s -H "Authorization: Bearer $koji_token" "$koji_url")
[[ -z "$response" ]] && echo "❌ Error fetching area list." && exit 1
areas=$(echo "$response" | jq -r '.data.features[].properties.name')

if [[ -n "$area" ]]; then
  if ! echo "$areas" | grep -Fxq "$area"; then
    echo "❌ Error: Area '$area' not found in API response."
    exit 1
  fi
  areas="$area"
fi

area_count=$(echo "$areas" | grep -c .)
[[ "$area_count" -eq 0 ]] && echo "❌ No areas found to import!" && exit 1

echo "[$(date)] ✅ Found $area_count area(s) to import."

output_file="import-areas.sh"
cat > "$output_file" <<EOF_SCRIPT
#!/bin/bash

# Config
enable_logs="${enable_logs}"
sleep_time_seconds=${sleep_time_seconds}
retry_count=${retry_count}
enable_retry=$([ "$enable_retry" = true ] && echo 1 || echo 0)
enable_parallel=$([ "$enable_parallel" = true ] && echo 1 || echo 0)
dry_run=$([ "$dry_run" = true ] && echo 1 || echo 0)
log_file="${log_file}"
importer_path="${importer_path}"
fletchling_config_dir="${fletchling_config_dir}"
fletchling_reload_url="${fletchling_reload_url}"

set -euo pipefail

log() {
  local msg="\$1"
  if [[ "\$enable_logs" == "yes" ]]; then
    echo "\$msg" | tee -a "\$log_file"
  else
    echo "\$msg"
  fi
}

run_import() {
  local area_name="\$1"
  local attempt=0
  local success=0
  while [[ \$attempt -le \$retry_count ]]; do
    if [[ "\$dry_run" -eq 1 ]]; then
      log "[\$(date)] DRY-RUN: Would import area: \$area_name"
      success=1
      break
    else
      log "[\$(date)] Importing area: \$area_name (Attempt \$((attempt+1)))"
      cd "\$importer_path" || return 1
      ./fletchling-osm-importer -f "\$fletchling_config_dir/fletchling.toml" "\$area_name"
      local res=\$?
      cd - >/dev/null || return 1
      if [[ \$res -eq 0 ]]; then
        success=1
        break
      fi
      log "[\$(date)] ❌ Import failed for \$area_name (Attempt \$((attempt+1)))"
    fi
    attempt=\$((attempt + 1))
  done
  if [[ \$success -ne 1 ]]; then
    log "[\$(date)] ❌ Failed to import \$area_name after \$retry_count retries."
    return 1
  fi
  return 0
}

echo "[\$(date)] Starting area imports..."
total_areas=$area_count
completed=0
start_time=\$(date +%s)
EOF_SCRIPT

if [[ "$enable_parallel" == true && "$parallel_jobs" -gt 1 ]]; then
  cat >> "$output_file" <<'EOF_SCRIPT'
run_area() {
  local area_name="$1"
  run_import "$area_name"
  completed=$((completed + 1))
  elapsed=$(( $(date +%s) - start_time ))
  remaining=$(( total_areas - completed ))
  estimated_remaining=$(( remaining * sleep_time_seconds ))
  progress=$(( completed * 100 / total_areas ))
  eta=$(date -d "+$estimated_remaining seconds" +"%H:%M:%S")
  log "[$(date)] ✅ Completed $completed/$total_areas areas ($progress%). ETA ~$((estimated_remaining / 60)) minutes ($eta)"
  [[ "$enable_logs" == "yes" ]] && echo "[$(date)] ✅ Log file updated after area: $area_name"
  [[ $completed -lt $total_areas ]] && sleep $sleep_time_seconds
}
EOF_SCRIPT

  while read -r area; do
    echo "while (( \$(jobs | wc -l) >= $parallel_jobs )); do sleep 1; done" >> "$output_file"
    echo "run_area \"$area\" &" >> "$output_file"
  done <<< "$areas"

  echo "wait" >> "$output_file"
else
  while read -r area; do
    cat >> "$output_file" <<EOF_SCRIPT
run_import "$area" || exit 1
completed=\$((completed + 1))
elapsed=\$(( \$(date +%s) - start_time ))
remaining=\$(( total_areas - completed ))
estimated_remaining=\$(( remaining * sleep_time_seconds ))
progress=\$(( completed * 100 / total_areas ))
eta=\$(date -d "+\$estimated_remaining seconds" +'%H:%M:%S')
log "[\$(date)] ✅ Completed \$completed/\$total_areas areas (\$progress%). ETA ~\$((estimated_remaining / 60)) minutes (\$eta)"
[[ \$completed -lt \$total_areas ]] && [[ "\$dry_run" -eq 0 ]] && sleep \$sleep_time_seconds

EOF_SCRIPT
  done <<< "$areas"
fi

cat >> "$output_file" <<'EOF_SCRIPT'

log "[\$(date)] 🔄 Reloading config after all imports..."
if [[ "$dry_run" -eq 1 ]]; then
  log "[\$(date)] DRY-RUN: Would reload fletchling config from $fletchling_reload_url"
else
  curl -X POST "$fletchling_reload_url"
fi

log "[\$(date)] 🏁 All imports completed."
EOF_SCRIPT

chmod +x "$output_file"
echo "[$(date)] ✅ Generated import script at '$output_file'."

if [[ "$run_immediately" == true ]]; then
  echo "[$(date)] Running generated import script..."
  bash "$output_file"
fi
