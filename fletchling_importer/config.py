import configparser
import os
from fletchling_importer import log

def load_config(path="config.ini"):
    if not os.path.exists(path):
        log.log("❌ config.ini not found!")
        raise FileNotFoundError("config.ini missing")

    config = configparser.ConfigParser()
    config.read(path)
    cfg = config["settings"]
    return {
        "koji_url": cfg.get("koji_url"),
        "koji_token": cfg.get("koji_token"),
        "reload_url": cfg.get("fletchling_reload_url"),
        "sleep_time": int(cfg.get("sleep_time_seconds", 120)),
        "enable_logs": cfg.get("enable_logs", "no") == "yes",
        "retry_count": int(cfg.get("retry_count", 0)),
        "parallel_jobs": int(cfg.get("parallel_jobs", 1)),
        "importer_path": cfg.get("importer_path", "./fletchling-osm-importer"),
    }
