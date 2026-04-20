#!/usr/bin/env bash
# reset.sh — shared helpers for fleet reset.sh wrappers.
#
# Sourceable. Caller controls shell options. Depends on jq.
# Registry functions require registry.sh to be sourced alongside.

# ---------------------------------------------------------------------------
# reset_check_live <FLEET_ROOT>
# Exit 2 if any process has FLEET_ROOT=<fleet_root> in its env. The caller is
# expected to bypass this check when --force is set.
# ---------------------------------------------------------------------------
reset_check_live() {
  local root="$1"
  local hits
  # Match either worker-spawn style (FLEET_ROOT='root') or kill.sh style
  # (<root>/workers). Also tolerate unquoted FLEET_ROOT=root.
  hits="$(pgrep -f "FLEET_ROOT=.{0,2}${root}" 2>/dev/null || true)"
  if [[ -z "${hits}" ]]; then
    hits="$(pgrep -f "${root}/workers" 2>/dev/null || true)"
  fi
  if [[ -n "${hits}" ]]; then
    echo "[reset] live worker processes detected under ${root}:" >&2
    echo "${hits}" | sed 's/^/  pid /' >&2
    echo "[reset] run kill.sh first, or pass --force to reset anyway." >&2
    return 2
  fi
  return 0
}

# ---------------------------------------------------------------------------
# reset_kill_live <FLEET_ROOT>
# Used by --force: SIGTERM then SIGKILL anything with FLEET_ROOT=<fleet_root>.
# ---------------------------------------------------------------------------
reset_kill_live() {
  local root="$1"
  local pids
  _reset_collect_pids() {
    local a b
    a="$(pgrep -f "FLEET_ROOT=.{0,2}${root}" 2>/dev/null || true)"
    b="$(pgrep -f "${root}/workers" 2>/dev/null || true)"
    printf '%s\n%s\n' "$a" "$b" | awk 'NF && !seen[$0]++'
  }
  pids="$(_reset_collect_pids)"
  [[ -z "${pids}" ]] && return 0
  echo "[reset] --force: killing ${pids//$'\n'/ }"
  # shellcheck disable=SC2086
  kill ${pids} 2>/dev/null || true
  sleep 1
  pids="$(_reset_collect_pids)"
  [[ -n "${pids}" ]] && kill -9 ${pids} 2>/dev/null || true
  return 0
}

# ---------------------------------------------------------------------------
# reset_clear_flags <FLEET_ROOT> [--dry-run]
# Remove .launch.lock, .launch.pid, .paused, .orch-state.json.
# ---------------------------------------------------------------------------
reset_clear_flags() {
  local root="$1"; local dry="${2:-}"
  local f
  for f in .launch.lock .launch.pid .paused .orch-state.json; do
    if [[ -e "${root}/${f}" ]]; then
      if [[ "${dry}" == "--dry-run" ]]; then
        echo "[reset] would clear ${f}"
      else
        rm -f "${root}/${f}"
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# reset_archive_outputs <FLEET_ROOT> [--dry-run]
# Move logs/, iterations/ into archive/<ts>/. For workers/, archive run
# artifacts (session.jsonl, status.json, .run.sh, .done, output/, *.cast,
# *.bak) per-worker but preserve prompt.md in place.
# ---------------------------------------------------------------------------
reset_archive_outputs() {
  local root="$1"; local dry="${2:-}"
  local ts; ts="$(date -u +"%Y%m%dT%H%M%SZ")"
  local dest="${root}/archive/${ts}"

  local any=0
  local d
  for d in logs iterations; do
    [[ -d "${root}/${d}" ]] && any=1
  done
  [[ -d "${root}/workers" ]] && any=1
  (( any == 0 )) && return 0

  if [[ "${dry}" == "--dry-run" ]]; then
    for d in logs iterations; do
      [[ -d "${root}/${d}" ]] && echo "[reset] would archive ${d}/ -> archive/${ts}/${d}/"
    done
    [[ -d "${root}/workers" ]] && echo "[reset] would archive run artifacts under workers/*/ -> archive/${ts}/workers/ (prompts preserved)"
    return 0
  fi

  mkdir -p "${dest}"
  for d in logs iterations; do
    [[ -d "${root}/${d}" ]] && mv "${root}/${d}" "${dest}/${d}"
  done

  if [[ -d "${root}/workers" ]]; then
    local wd wid wdest
    for wd in "${root}/workers"/*/; do
      [[ -d "${wd}" ]] || continue
      wid="$(basename "${wd}")"
      wdest="${dest}/workers/${wid}"
      mkdir -p "${wdest}"
      local item
      for item in session.jsonl status.json .run.sh .done output; do
        [[ -e "${wd}${item}" ]] && mv "${wd}${item}" "${wdest}/${item}"
      done
      # Move any .cast or .bak files
      local f
      for f in "${wd}"*.cast "${wd}"*.bak; do
        [[ -e "$f" ]] && mv "$f" "${wdest}/"
      done
    done
  fi
  echo "${dest}"
}

# ---------------------------------------------------------------------------
# reset_fleet_json <FLEET_ROOT> [--dry-run]
# jq rewrite: drop fleet-level status/launched_at/killed_at/completed_at/
# stop_reason/paused_at, and per-worker status/started_at/session_name.
# ---------------------------------------------------------------------------
reset_fleet_json() {
  local root="$1"; local dry="${2:-}"
  local fj="${root}/fleet.json"
  [[ -f "${fj}" ]] || return 0

  if [[ "${dry}" == "--dry-run" ]]; then
    echo "[reset] would reset status fields in fleet.json"
    return 0
  fi

  local tmp; tmp="$(mktemp "${fj}.XXXXXX")"
  jq '
    del(.status, .launched_at, .killed_at, .completed_at, .stop_reason, .paused_at)
    | .workers |= (map(del(.status, .started_at, .session_name)))
  ' "${fj}" > "${tmp}" && mv "${tmp}" "${fj}" || { rm -f "${tmp}"; return 1; }
}

# ---------------------------------------------------------------------------
# reset_hard_wipe <FLEET_ROOT> [--dry-run]
# rm -rf artifact dirs + ledger files. Preserves fleet.json and each
# workers/{id}/prompt.md.
# ---------------------------------------------------------------------------
reset_hard_wipe() {
  local root="$1"; local dry="${2:-}"
  local targets=(logs iterations archive directives shared)
  local files=(.cost-ledger.jsonl results.tsv)

  if [[ "${dry}" == "--dry-run" ]]; then
    local t
    for t in "${targets[@]}"; do [[ -e "${root}/${t}" ]] && echo "[reset] would rm -rf ${t}/"; done
    for t in "${files[@]}";   do [[ -e "${root}/${t}" ]] && echo "[reset] would rm ${t}"; done
    [[ -d "${root}/workers" ]] && echo "[reset] would wipe workers/*/ contents (prompt.md preserved)"
    return 0
  fi

  local t
  for t in "${targets[@]}"; do [[ -e "${root}/${t}" ]] && rm -rf "${root}/${t}"; done
  for t in "${files[@]}";   do [[ -e "${root}/${t}" ]] && rm -f "${root}/${t}"; done

  # Per-worker: wipe everything except prompt.md
  if [[ -d "${root}/workers" ]]; then
    local wd item f
    for wd in "${root}/workers"/*/; do
      [[ -d "${wd}" ]] || continue
      find "${wd}" -mindepth 1 -maxdepth 1 ! -name 'prompt.md' -exec rm -rf {} +
    done
  fi
}

# ---------------------------------------------------------------------------
# reset_unregister_fleet <FLEET_ROOT>
# Resolves fleet_name from fleet.json and calls registry_unregister.
# Requires registry.sh sourced.
# ---------------------------------------------------------------------------
reset_unregister_fleet() {
  local root="$1"
  local fj="${root}/fleet.json"
  [[ -f "${fj}" ]] || return 0
  local name; name="$(jq -r '.fleet_name // empty' "${fj}")"
  [[ -z "${name}" ]] && return 0
  if declare -f registry_unregister >/dev/null 2>&1; then
    registry_unregister "${name}" || true
  fi
}
