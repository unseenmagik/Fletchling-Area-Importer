#!/bin/bash
set -euo pipefail

# Load config.ini
config_file="config.ini"
if [[ ! -f "$config_file" ]]; then
  echo "❌ Config file '$config_file' not found!"
  exit 1
fi

# Read config values (simple parsing)
declare -A config
while IFS='=' read -r key value; do
  key=$(echo "$key" | tr -d ' ')
  value=$(echo "$value" | tr -d ' ' | tr -d '"')
  [[ -z "$key" || "$key" =~ ^# ]] && continue
  config[$key]="$value"
done < "$config_file"

koji_url=${config[koji_url]:-}
koji_token=${config[koji_token]:-}
fletchling_reload_url=${config[fletchling_reload_url]:-}
sleep_time_seconds=${config[sleep_time_seconds]:-120}
enable_logs=${config[enable_logs]:-no}
retry_count=${config[retry_count]:-0}
parallel_jobs=${config[parallel_jobs]:-1}
importer_path=${config[importer_path]:-./fletchling-osm-importer}  # ✅ NEW

# Defaults for CLI flags
area=""
run_immediately=false
enable_retry=false
enable_parallel=false
dry_run=false
clear_log=false

print_help() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -a          Generate import script for only the specified area. Example: -a "AreaName"
  -i          Run the generated import script after creating it
  -r          Enable retries per area import (count from config.ini)
  -p          Enable parallel imports (count from config.ini)
  -d          Dry-run mode; print commands without executing them
  -cl         Clear the log file before running
  -h, --help  Show this help message and exit

Examples:
  $0
  $0 -a "AreaName"
  $0 -i
  $0 -r -p
  $0 -d -a "AreaName"
  $0 -cl
EOF
}

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -a)
      shift
      if [[ $# -gt 0 ]]; then
        area="$1"
      else
        echo "❌ Error: -a requires an argument."
        exit 1
      fi
      ;;
    -i)
      run_immediately=true
      ;;
    -r)
      enable_retry=true
      ;;
    -p)
      enable_parallel=true
      ;;
    -d)
      dry_run=true
      ;;
    -cl)
      clear_log=true
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "❌ Unknown option: $1"
      print_help
      exit 1
      ;;
  esac
  shift
done

echo "[$(date)] Starting import script generation..."

echo "[$(date)] Config summary:"
echo "  Koji URL: $koji_url"
echo "  Retry enabled: $enable_retry (count: $retry_count)"
echo "  Parallel enabled: $enable_parallel (jobs: $parallel_jobs)"
echo "  Dry-run mode: $dry_run"
echo "  Sleep time seconds: $sleep_time_seconds"
echo "  Importer path: $importer_path"
if [[ -n "$area" ]]; then
  echo "  Single area mode: $area"
else
  echo "  Full area list mode"
fi
if [[ "$clear_log" == true ]]; then
  echo "  Log clearing: Enabled"
fi

# Clear log file if requested
log_file="import-areas.log"
if [[ "$clear_log" == true ]]; then
  if [[ -f "$log_file" ]]; then
    echo "[$(date)] Clearing log file: $log_file"
    > "$log_file"
  fi
fi

# Fetch areas from API
echo "[$(date)] Fetching area list from API..."
response=$(curl -s -H "Authorization: Bearer $koji_token" "$koji_url")
if [[ $? -ne 0 || -z "$response" ]]; then
  echo "[$(date)] ❌ Error fetching area list."
  exit 1
fi

# Extract area names
areas=$(echo "$response" | jq -r '.data.features[].properties.name')

# If single area specified, filter it
if [[ -n "$area" ]]; then
  # Check if area exists in list
  if ! echo "$areas" | grep -Fxq "$area"; then
    echo "[$(date)] ❌ Error: Specified area '$area' not found in API results."
    exit 1
  fi
  areas="$area"
fi

area_count=$(echo "$areas" | grep -c .)
if [[ "$area_count" -eq 0 ]]; then
  echo "[$(date)] ❌ No areas found to import!"
  exit 1
fi

echo "[$(date)] ✅ Found $area_count area(s) to import."

# Output file
output_file="import-areas.sh"

# Start writing the import script
cat > "$output_file" <<EOF
#!/bin/bash
set -euo pipefail

enable_logs="$enable_logs"
sleep_time_seconds=$sleep_time_seconds
retry_count=$retry_count
enable_retry=$([ "$enable_retry" = true ] && echo 1 || echo 0)
enable_parallel=$([ "$enable_parallel" = true ] && echo 1 || echo 0)
dry_run=$([ "$dry_run" = true ] && echo 1 || echo 0)

log_file="$log_file"
importer_path="$importer_path"

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
      "\$importer_path" "\$area_name"
      if [[ \$? -eq 0 ]]; then
        success=1
        break
      else
        log "[\$(date)] ❌ Import failed for \$area_name (Attempt \$((attempt+1)))"
      fi
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

EOF

if [[ "$enable_parallel" == true && "$parallel_jobs" -gt 1 ]]; then
  cat >> "$output_file" <<'EOF'
pids=()
run_area() {
  local area_name="$1"
  run_import "$area_name"
  local status=$?
  if [[ $status -ne 0 ]]; then
    echo "[$(date)] ❌ Area import failed: $area_name"
  fi
  completed=$((completed + 1))
  elapsed=$(( $(date +%s) - start_time ))
  remaining=$(( total_areas - completed ))
  estimated_remaining=$(( remaining * sleep_time_seconds ))
  progress=$(( completed * 100 / total_areas ))
  eta=$(date -d "+$estimated_remaining seconds" +"%H:%M:%S")
  echo "[$(date)] ✅ Completed $completed/$total_areas areas ($progress%). ETA ~$((estimated_remaining / 60)) minutes ($eta)"
  if [[ "$enable_logs" == "yes" ]]; then
    echo "[$(date)] ✅ Log file updated after area: $area_name"
  fi
  if [[ $completed -lt $total_areas ]]; then
    sleep $sleep_time_seconds
  fi
}

EOF

  while read -r area; do
    cat >> "$output_file" <<EOF
while (( \$(jobs | wc -l) >= $parallel_jobs )); do
  sleep 1
done
run_area "$area" &
EOF
  done <<< "$areas"

  cat >> "$output_file" <<'EOF'

wait

echo "[$(date)] 🔄 Reloading config after all imports..."
if [[ "$dry_run" -eq 0 ]]; then
  curl "$fletchling_reload_url"
fi
echo "[$(date)] ✅ Config reload complete."
EOF

else
  while read -r area; do
    cat >> "$output_file" <<EOF
run_import "$area" || exit 1
completed=\$((completed + 1))
elapsed=\$(( \$(date +%s) - start_time ))
remaining=\$(( total_areas - completed ))
estimated_remaining=\$(( remaining * sleep_time_seconds ))
progress=\$(( completed * 100 / total_areas ))
eta=\$(date -d "+\$estimated_remaining seconds" +'%H:%M:%S')
log "[\$(date)] ✅ Completed \$completed/\$total_areas areas (\$progress%). ETA ~\$((estimated_remaining / 60)) minutes (\$eta)"
if [[ "\$enable_logs" == "yes" ]]; then
  log "[\$(date)] ✅ Log file updated after area: $area"
fi
if [[ \$completed -lt \$total_areas ]]; then
  if [[ "\$dry_run" -eq 0 ]]; then
    sleep \$sleep_time_seconds
  fi
fi

EOF
  done <<< "$areas"

  cat >> "$output_file" <<EOF

echo "[\$(date)] 🔄 Reloading config after all imports..."
if [[ "\$dry_run" -eq 0 ]]; then
  curl "$fletchling_reload_url"
fi
echo "[\$(date)] ✅ Config reload complete."
EOF
fi

chmod +x "$output_file"

echo "[$(date)] ✅ Script '$output_file' created successfully with $area_count area(s)."

if [[ "$run_immediately" = true ]]; then
  echo "[$(date)] Running the generated import script now..."
  if [[ "$dry_run" = true ]]; then
    bash "$output_file"
  else
    ./"$output_file"
  fi
fi
