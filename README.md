# 🐦 Fletchling Area Importer

A configurable CLI tool to automate the import of area data into your Fletchling databse, based on API data from Koji.

---

## 🚀 Features

- Fetches area list from Koji API
- Generates and executes import commands per area
- Supports:
  - ✅ Retries per area
  - ✅ Parallel imports
  - ✅ Dry-run mode
  - ✅ Optional logging
  - ✅ Configurable sleep interval
- CLI-friendly with flag-based control
- Easily extendable and production-ready
- GitHub Actions CI support

---

## 📦 Requirements

- Python 3.8+
- `fletchling-osm-importer` (must be built and accessible via path)

Install dependencies:

```bash
cd Fletchling-Area-Importer
pip install -r requirements.txt
```

---

## ⚙️ Configuration
Create a config.ini file in the project root:
`cp config.ini.example config.ini`

```ini
[settings]
koji_url = http://127.0.0.1:1234/api/v1/geofence/feature-collection/{project}
koji_token = kojiToken
fletchling_reload_url = http://127.0.0.1:1234/api/config/reload
sleep_time_seconds = 60
enable_logs = yes
retry_count = 2
parallel_jobs = 2
importer_path = /absolute/path/to/fletchling-osm-importer
```

---

## 🧪 Usage

Run the CLI with:

```bash
python -m fletchling_importer [options]
```

### 🔹 Options

| Flag | Description |
|------|-------------|
| `-a`, `--area`         | Run for a specific area only |
| `-i`, `--immediate`    | Run immediately after generating script |
| `-r`, `--retry`        | Enable retries per area (count from config) |
| `-p`, `--parallel`     | Enable parallel imports (jobs from config) |
| `-d`, `--dry-run`      | Print commands without executing |
| `-cl`, `--clear-log`   | Clear log file before running |
| `-h`, `--help`         | Show CLI help |

### 🔹 Examples

```bash
# Import all areas
python -m fletchling_importer

# Dry-run for a specific area
python -m fletchling_importer -a "MyArea" -d

# Run with retries and parallel imports
python -m fletchling_importer -r -p -i
```

---

## 🧪 CI/CD

This repo includes a GitHub Actions workflow to:

- Install dependencies via `requirements.txt`
- Run all tests in the `tests/` folder

Runs on:
- Push to `python` branch
- Pull Requests into `python`

---

## 📁 Project Structure

```text
.
├── fletchling_importer/
│   ├── __init__.py
│   ├── main.py
│   └── utils.py
├── tests/
│   └── test_dummy.py
├── config.ini
├── requirements.txt
├── pyproject.toml
├── README.md
└── .github/
    └── workflows/
        └── ci.yml
```

---

## 🛠️ Roadmap

- [ ] Add unit tests for parallel and retry logic
- [ ] Add flag to specify custom config path
- [ ] Package as installable CLI (`pip install .`)
- [ ] Docker support

---

## 📃 License

MIT License. See [LICENSE](LICENSE) for details.

---
