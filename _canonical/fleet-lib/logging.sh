#!/usr/bin/env bash
# _lib/logging.sh — shared color constants and logging helpers for fleet skills

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Logging helpers — callers can override LOG_PREFIX (default: "launch")
: "${LOG_PREFIX:=launch}"

info()    { echo -e "${CYAN}[${LOG_PREFIX}]${NC} $*"; }
success() { echo -e "${GREEN}[${LOG_PREFIX}]${NC} $*"; }
warn()    { echo -e "${YELLOW}[${LOG_PREFIX}]${NC} $*"; }
error()   { echo -e "${RED}[${LOG_PREFIX}]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }
