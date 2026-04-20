# registry.sh — shared fleet-name registry helper (source-able)
#
# Provides a JSON-backed map of fleet_name -> fleet_root (plus pid, started_at)
# so commands like kill.sh / view.sh / feed.sh / status.sh can accept either
# a full path or just the fleet name.
#
# Canonical location: ~/.claude/fleet-registry.json
# Schema: [ { "name": "...", "root": "...", "started_at": "...", "pid": N }, ... ]
#
# All writers use tempfile + mv for atomic replacement. Readers tolerate a
# corrupt file by treating it as empty `[]` and warning on stderr.
#
# This file is intended to be sourced. It defines functions only; the caller
# controls shell options (set -euo pipefail etc).

# ---------------------------------------------------------------------------
# registry_path — echo the canonical registry path, creating an empty file
# if it does not yet exist.
# ---------------------------------------------------------------------------
registry_path() {
  local path="${FLEET_REGISTRY_PATH:-${HOME}/.claude/fleet-registry.json}"
  if [[ ! -f "${path}" ]]; then
    mkdir -p "$(dirname "${path}")" 2>/dev/null || true
    printf '[]\n' > "${path}" 2>/dev/null || true
  fi
  printf '%s\n' "${path}"
}

# ---------------------------------------------------------------------------
# _registry_read_safe — cat the registry to stdout; if jq can't parse it,
# emit `[]` and warn on stderr. Never exits nonzero.
# ---------------------------------------------------------------------------
_registry_read_safe() {
  local path
  path="$(registry_path)"
  if ! jq empty "${path}" 2>/dev/null; then
    echo "[registry] warning: ${path} is corrupt or unreadable; treating as empty" >&2
    printf '[]'
    return 0
  fi
  cat "${path}"
}

# ---------------------------------------------------------------------------
# registry_register <fleet_root> <fleet_name> [pid]
# Atomically upsert an entry keyed by name. pid defaults to $$.
# ---------------------------------------------------------------------------
registry_register() {
  local fleet_root="${1:-}"
  local fleet_name="${2:-}"
  local pid="${3:-$$}"

  if [[ -z "${fleet_root}" || -z "${fleet_name}" ]]; then
    echo "[registry] registry_register: fleet_root and fleet_name are required" >&2
    return 1
  fi

  local path
  path="$(registry_path)"
  local resolved_root
  resolved_root="$(realpath "${fleet_root}" 2>/dev/null || echo "${fleet_root}")"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  local current
  current="$(_registry_read_safe)"

  local tmp
  tmp="$(mktemp "${path}.XXXXXX")" || return 1

  if ! printf '%s' "${current}" | jq \
      --arg name "${fleet_name}" \
      --arg root "${resolved_root}" \
      --arg ts   "${ts}" \
      --argjson pid "${pid}" \
      '
        (map(select(.name != $name))) +
        [ { name: $name, root: $root, started_at: $ts, pid: $pid } ]
      ' > "${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    echo "[registry] failed to update ${path}" >&2
    return 1
  fi

  mv "${tmp}" "${path}"
}

# ---------------------------------------------------------------------------
# registry_unregister <fleet_name>
# Atomically remove an entry by name. Silent no-op if not present.
# ---------------------------------------------------------------------------
registry_unregister() {
  local fleet_name="${1:-}"
  if [[ -z "${fleet_name}" ]]; then
    echo "[registry] registry_unregister: fleet_name is required" >&2
    return 1
  fi

  local path
  path="$(registry_path)"
  local current
  current="$(_registry_read_safe)"
  local tmp
  tmp="$(mktemp "${path}.XXXXXX")" || return 1

  if ! printf '%s' "${current}" | jq \
      --arg name "${fleet_name}" \
      'map(select(.name != $name))' > "${tmp}" 2>/dev/null; then
    rm -f "${tmp}"
    echo "[registry] failed to update ${path}" >&2
    return 1
  fi

  mv "${tmp}" "${path}"
}

# ---------------------------------------------------------------------------
# registry_resolve <name_or_path>
# If arg is an existing directory, echo its realpath. Otherwise look up the
# name in the registry and echo the stored root. Return 1 (with stderr msg)
# if neither matches.
# ---------------------------------------------------------------------------
registry_resolve() {
  local arg="${1:-}"
  if [[ -z "${arg}" ]]; then
    echo "[registry] registry_resolve: argument required" >&2
    return 1
  fi

  if [[ -d "${arg}" ]]; then
    realpath "${arg}"
    return 0
  fi

  local current
  current="$(_registry_read_safe)"
  local root
  root="$(printf '%s' "${current}" \
    | jq -r --arg name "${arg}" \
        '.[] | select(.name == $name) | .root' 2>/dev/null \
    | head -1)"

  if [[ -z "${root}" || "${root}" == "null" ]]; then
    echo "[registry] fleet not found: ${arg}" >&2
    echo "[registry]   (not a directory, and no registry entry with that name)" >&2
    echo "[registry]   registry: $(registry_path)" >&2
    return 1
  fi

  if [[ ! -d "${root}" ]]; then
    echo "[registry] registry entry '${arg}' points at missing dir: ${root}" >&2
    return 1
  fi

  printf '%s\n' "${root}"
}

# ---------------------------------------------------------------------------
# registry_list — pretty-print all known fleets, one per line.
# Marks dead pids with a gray [dead] suffix.
# ---------------------------------------------------------------------------
registry_list() {
  local GRAY='\033[0;37m'
  local NC='\033[0m'

  local current
  current="$(_registry_read_safe)"

  local count
  count="$(printf '%s' "${current}" | jq 'length' 2>/dev/null || echo 0)"
  if [[ "${count}" == "0" ]]; then
    echo "(no fleets registered)"
    return 0
  fi

  printf '%s' "${current}" \
    | jq -r '.[] | "\(.name)\t\(.root)\t\(.pid)\t\(.started_at)"' 2>/dev/null \
    | while IFS=$'\t' read -r name root pid started; do
        local suffix=""
        if [[ -n "${pid}" && "${pid}" != "null" ]]; then
          if ! kill -0 "${pid}" 2>/dev/null; then
            suffix=" ${GRAY}[dead]${NC}"
          fi
        fi
        printf "%s  %s  pid=%s  started=%s%b\n" \
          "${name}" "${root}" "${pid}" "${started}" "${suffix}"
      done
}
