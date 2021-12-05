#!/usr/bin/env bash
set -eo pipefail

SELF=$(basename "$(readlink -f "${0}")")

[[ -z "${STEAM_ROOT}" ]] && STEAM_ROOT="${XDG_DATA_HOME:-${HOME}/.local/share}/Steam"
STEAM_ROOT="${STEAM_ROOT}/steamapps"

DAYZ_ID=221100
DIR_WORKSHOP="${STEAM_ROOT}/workshop/content/${DAYZ_ID}"
DIR_DAYZ="${STEAM_ROOT}/common/DayZ"

API_URL="https://api.daemonforge.dev/server/@ADDRESS@/@PORT@/full"
API_PARAMS=(
  -sSL
  -H "Referer: https://daemonforge.dev/"
  -H "User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.45 Safari/537.36"
)

DEBUG=0
LAUNCH=0
SERVER=""
PORT="27016"
INPUT=()

declare -A DEPS=(
  [gawk]=gawk
  [curl]=curl
  [jq]=jq
  [steam]=steam
)

while (( "$#" )); do
  case "${1}" in
    -d|--debug)
      DEBUG=1
      ;;
    -l|--launch)
      LAUNCH=1
      ;;
    -s|--server)
      SERVER="${2}"
      shift
      ;;
    -p|--port)
      PORT="${2}"
      shift
      ;;
    *)
      INPUT+=("${1}")
      ;;
  esac
  shift
done


# ----


err() {
  echo >&2 "[${SELF}][error] ${@}"
  exit 1
}

msg() {
  echo "[${SELF}][info] ${@}"
}

debug() {
  [[ ${DEBUG} == 1 ]] && echo "[${SELF}][debug] ${@}"
}

check_dir() {
  [[ -d "${1}" ]] || err "Invalid/missing directory: ${1}"
}


# ----


for dep in "${!DEPS[@]}"; do
  command -v "${dep}" 2>&1 >/dev/null || err "${DEPS["${dep}"]} is missing. Aborting."
done

check_dir "${DIR_DAYZ}"
check_dir "${DIR_WORKSHOP}"

if [[ -n "${SERVER}" ]]; then
  msg "Querying API for server: ${SERVER}:${PORT}"
  query="$(sed -e "s/@ADDRESS@/${SERVER}/" -e "s/@PORT@/${PORT}/" <<< "${API_URL}")"
  debug "Querying ${query}"
  response="$(curl "${API_PARAMS[@]}" "${query}")"
  INPUT+=( $(jq -r ".mods[] | select(.app_id == ${DAYZ_ID}) | .id" <<< "${response}") )
fi

mods=()
for modid in "${INPUT[@]}"; do
  modpath="${DIR_WORKSHOP}/${modid}"
  [[ -d "${modpath}" ]] || err "Missing mod directory for: ${modid}"

  modmeta="${modpath}/meta.cpp"
  [[ -f "${modmeta}" ]] || err "Missing mod metadata for: ${modid}"

  modname="$(gawk 'match($0,/name\s*=\s*"(.+)"/,m){print m[1];exit}' "${modmeta}")"
  [[ -n "${modname}" ]] || err "Missing mod name for: ${modid}"
  debug "Mod ${modid} found: ${modname}"

  if ! [[ -L "${DIR_DAYZ}/@${modname}" ]]; then
    msg "Creating mod symlink for: ${modname}"
    ln -sr "${modpath}" "${DIR_DAYZ}/@${modname}"
  fi

  mods+=("@${modname}")
done

cmdline=()
if [[ "${#mods[@]}" -gt 0 ]]; then
  cmdline+=("\"-mod=$(IFS=";"; echo "${mods[*]}")\"")
fi

if [[ "${LAUNCH}" == 1 ]]; then
  set -x
  steam -applaunch "${DAYZ_ID}" "${cmdline[@]}"
else
  echo "${cmdline[@]}"
fi
