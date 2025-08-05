import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timedelta
from fletchling_importer import log

def run_import(area_name, cfg, retry, dry_run):
    retries = cfg["retry_count"] if retry else 0
    importer_path = cfg["importer_path"]
    sleep_time = cfg["sleep_time"]

    for attempt in range(retries + 1):
        if dry_run:
            log.log(f"DRY-RUN: Would import area: {area_name}")
            return True
        try:
            log.log(f"Importing area: {area_name} (Attempt {attempt + 1})")
            subprocess.run([importer_path, area_name], check=True)
            log.log(f"✅ Import successful: {area_name}")
            return True
        except subprocess.CalledProcessError:
            log.log(f"❌ Import failed for {area_name} (Attempt {attempt + 1})")
            if attempt < retries:
                time.sleep(sleep_time)
    log.log(f"❌ Failed to import {area_name} after {retries} retries.")
    return False

def run_all_imports(areas, cfg, retry=False, parallel=False, dry_run=False):
    total = len(areas)
    completed = 0
    start_time = time.time()
    sleep_time = cfg["sleep_time"]
    parallel_jobs = cfg["parallel_jobs"]

    def progress():
        nonlocal completed
        completed += 1
        remaining = total - completed
        eta_seconds = remaining * sleep_time
        percent = int((completed / total) * 100)
        eta = datetime.now() + timedelta(seconds=eta_seconds)
        log.log(f"✅ Completed {completed}/{total} areas ({percent}%). ETA ~{eta_seconds // 60} min ({eta.strftime('%H:%M:%S')})")

    if parallel and parallel_jobs > 1:
        with ThreadPoolExecutor(max_workers=parallel_jobs) as executor:
            futures = {
                executor.submit(run_import, area, cfg, retry, dry_run): area
                for area in areas
            }
            for future in as_completed(futures):
                area = futures[future]
                future.result()
                progress()
    else:
        for area in areas:
            run_import(area, cfg, retry, dry_run)
            progress()
            if not dry_run and completed < total:
                time.sleep(sleep_time)
