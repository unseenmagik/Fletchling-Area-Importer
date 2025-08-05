import argparse
import time
import requests
from fletchling_importer import config, importer, log

def main():
    args = parse_args()
    cfg = config.load_config()

    log.ENABLE_LOGS = cfg["enable_logs"]
    if args.clear_log:
        open(log.LOG_FILE, "w").close()
        log.log("Log file cleared.")

    log.log("Fetching area list...")
    areas = fetch_area_list(cfg["koji_url"], cfg["koji_token"])
    if args.area:
        if args.area not in areas:
            log.log(f"❌ Area '{args.area}' not found.")
            return
        areas = [args.area]

    importer.run_all_imports(
        areas,
        cfg,
        retry=args.retry,
        parallel=args.parallel,
        dry_run=args.dry_run
    )

    if not args.dry_run:
        log.log("🔄 Reloading config...")
        try:
            requests.get(cfg["reload_url"])
            log.log("✅ Config reload complete.")
        except Exception as e:
            log.log(f"⚠️ Reload failed: {e}")

def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("-a", "--area")
    parser.add_argument("-i", "--immediate", action="store_true")
    parser.add_argument("-r", "--retry", action="store_true")
    parser.add_argument("-p", "--parallel", action="store_true")
    parser.add_argument("-d", "--dry-run", action="store_true")
    parser.add_argument("-cl", "--clear-log", action="store_true")
    return parser.parse_args()
