# Area Import Script Generator

This repository contains a Bash script to generate and run area import scripts for Fletchling. It automates fetching area lists from a Koji API, generates an import script that imports each area with logging, ETA, retries, and optional parallelism, then reloads the configuration at the end.

---

## Features

- Fetch area list dynamically from Koji API
- Generate an import shell script with:
  - Progress percentage and ETA logging
  - Configurable sleep time between imports
  - Retry logic for failed imports
  - Parallel imports support
  - Dry-run mode to preview actions without execution
  - Log file with detailed timestamps
- Clear log file option before running
- Command line options to:
  - Import a single area
  - Run the generated import script immediately
  - Show help menu

---

## Requirements

- Bash shell (tested on Linux/macOS)
- `curl` and `jq` installed
- Access to Koji API and Fletchling services
- `fletchling-osm-importer` executable in the PATH or same directory

---

## Installation

1. Clone this repo:
   ```bash
   git clone https://github.com/yourusername/area-import-generator.git
   cd area-import-generator
   cp config.ini.example config.ini
   ```

2. Configure your settings in `config.ini`:
      ```ini
   # Set your koji url and project to read areas from.   
   koji_url="http://127.0.0.1:1234/api/v1/geofence/feature-collection/{project}"
   # Koji bearer/auth token  
   koji_token="setToken"
   # Fletchling reload url
   fletchling_reload_url="http://127.0.0.1:1234/api/config/reload"
   # Sleep time in seconds between calling OSM Importer. [default=120s]
   sleep_time_seconds=120
   # Enable logging [yes|no]
   enable_logs=yes
   # Retry attempts incase of OSM failure
   retry_count=2
   # Paralled processing of OSM areas. [default=1]
   parallel_jobs=1
   # Log file name
   log_file="import-areas.log"
   ```

4. Make the generator script executable:
   ```bash
   chmod +x generate-import-script.sh
   ```

---

## Usage

Run the generator script with optional flags:

```bash
./generate-import-script.sh [OPTIONS]
```

### Options

| Flag         | Description                                                                                      |
|--------------|------------------------------------------------------------------------------------------------|
| `-a "AreaName"` | Generate import script for only the specified area                                            |
| `-i`         | Run the generated import script immediately after creation                                      |
| `-r`         | Use retry count from config (number of retries per area import)                                |
| `-p`         | Use parallel jobs from config (number of parallel imports)                                     |
| `-cl`        | Clear the log file before running                                                              |
| `-h`         | Show this help menu                                                                             |

### Examples

Generate import script for all areas:

```bash
./generate-import-script.sh
```

Generate import script for one area:

```bash
./generate-import-script.sh -a "AreaName"
```

Generate and run import script immediately:

```bash
./generate-import-script.sh -i
```

Clear log and run import script immediately:

```bash
./generate-import-script.sh -cl -i
```

---

## Logs

Logs are written to the file specified in `config.ini` (default: `import-areas.log`). The log includes timestamps, progress percentage, ETA, retries, and confirmation of log updates after each area.

---

## License

This project is licensed under the **GNU General Public License v3.0**.

---

## Contact

Please open an issue for bugs, feature requests, or suggestions.
