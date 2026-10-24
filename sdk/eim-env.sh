#!/bin/bash
# eim-env.sh — resolve an ESP-IDF installation managed by EIM
# (ESP-IDF Installation Manager).
#
# Sourced by the SDK scripts. Usage:
#
#   . "$SCRIPT_DIR/eim-env.sh"
#   eim_env_resolve [name-or-id]
#
# With no argument the installation selected by `eim select` is used.
# Exports:
#   EIM_IDF_NAME         EIM name of the installation (for example "v6.1")
#   IDF_PATH             ESP-IDF checkout
#   IDF_TOOLS_PATH       EIM tools directory (toolchains, python env, ...)
#   IDF_ACTIVATION_SCRIPT  shell activation script written by EIM
#
# The EIM state file is read from $EIM_IDF_JSON, or the EIM default
# (~/.espressif/tools/eim_idf.json).

eim_env_json_file() {
  printf '%s\n' "${EIM_IDF_JSON:-$HOME/.espressif/tools/eim_idf.json}"
}

eim_env_resolve() {
  local requested="${1:-}"
  local json
  json="$(eim_env_json_file)"

  if [[ ! -f "$json" ]]; then
    echo "error: EIM configuration not found: $json" >&2
    echo "       install ESP-IDF with: eim install -i v6.1 -t ${IDF_TARGET:-esp32c6}" >&2
    echo "       or pass --idf-path /path/to/esp-idf" >&2
    return 1
  fi

  local assignments
  assignments="$(python3 - "$json" "$requested" <<'PY'
import json
import shlex
import sys

path, requested = sys.argv[1], sys.argv[2]
try:
    with open(path) as handle:
        doc = json.load(handle)
except (OSError, ValueError) as error:
    sys.exit(f"cannot read {path}: {error}")

installs = doc.get("idfInstalled") or []
selected = doc.get("idfSelectedId")
entry = None

# Ignore half-installed entries when choosing a version.
finished = [i for i in installs if i.get("status") == "finished"] or installs

if requested:
    matches = [i for i in finished if requested in (i.get("name"), i.get("id"))]
    entry = matches[0] if matches else None
    if entry is None:
        available = sorted({i.get("name", "?") for i in installs})
        sys.exit(f"no EIM ESP-IDF installation named {requested!r} (available: {', '.join(available) or 'none'})")
else:
    for candidate in finished:
        if candidate.get("id") == selected:
            entry = candidate
            break
    if entry is None and finished:
        entry = finished[0]

if entry is None:
    sys.exit("no EIM-managed ESP-IDF installation found; run: eim install -i v6.1 -t esp32c6")

for key, variable in (
    ("name", "EIM_IDF_NAME"),
    ("path", "IDF_PATH"),
    ("idfToolsPath", "IDF_TOOLS_PATH"),
    ("activationScript", "IDF_ACTIVATION_SCRIPT"),
):
    print(f"{variable}={shlex.quote(entry.get(key) or '')}")
PY
)" || return 1

  eval "$assignments"
  export EIM_IDF_NAME IDF_PATH IDF_TOOLS_PATH IDF_ACTIVATION_SCRIPT

  if [[ -z "${IDF_PATH:-}" ]]; then
    echo "error: EIM installation has no IDF path in $json" >&2
    return 1
  fi
  if [[ -z "${IDF_ACTIVATION_SCRIPT:-}" || ! -f "$IDF_ACTIVATION_SCRIPT" ]]; then
    echo "error: EIM activation script not found for ${EIM_IDF_NAME:-installation}" >&2
    echo "       expected: ${IDF_ACTIVATION_SCRIPT:-<none>}" >&2
    echo "       repair with: eim fix ${EIM_IDF_NAME:-}" >&2
    return 1
  fi
}
