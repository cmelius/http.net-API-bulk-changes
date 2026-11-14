#!/usr/bin/env bash
#
# update-ttl.sh - bulk change the TTL of A records at http.net (Linux/macOS port of update-ttl.ps1)
#
# Requirements: bash 4+, curl, jq
#
# Configuration (in this order of precedence):
#   1. command line options (see --help)
#   2. environment variables HTTPNET_API_KEY, TARGET_IP, NEW_TTL, TEST_DOMAIN
#   3. the defaults below
#
set -euo pipefail

# --- Defaults (adjust or use env vars / options) ------------------------------
API_KEY="${HTTPNET_API_KEY:-<api-key>}"
TARGET_IP="${TARGET_IP:-<server-ip>}"
NEW_TTL="${NEW_TTL:-300}"            # 5 minutes
TEST_DOMAIN="${TEST_DOMAIN:-<test-domain>}"

BASE_URL="${HTTPNET_BASE_URL:-https://partner.http.net/api/dns/v1/json}"
PAGE_LIMIT=100

MODE="test"     # test = only TEST_DOMAIN, all = every zone in the account
DRY_RUN=0

# --- Output helpers ----------------------------------------------------------
if [[ -t 1 ]]; then
    C_GRAY=$'\e[90m'; C_GREEN=$'\e[32m'; C_RED=$'\e[31m'; C_YELLOW=$'\e[33m'; C_RESET=$'\e[0m'
else
    C_GRAY=""; C_GREEN=""; C_RED=""; C_YELLOW=""; C_RESET=""
fi
debug() { echo "${C_GRAY}DEBUG: $*${C_RESET}"; }
info()  { echo "$*"; }
ok()    { echo "${C_GREEN}$*${C_RESET}"; }
warn()  { echo "${C_YELLOW}$*${C_RESET}"; }
err()   { echo "${C_RED}$*${C_RESET}" >&2; }

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Lowers/changes the TTL of all A records pointing to a given IP at http.net.
Without --all only the test domain is processed.

Options:
  -k, --api-key KEY      http.net API key            (env: HTTPNET_API_KEY)
  -i, --ip IP            only A records with this IP (env: TARGET_IP)
  -t, --ttl SECONDS      new TTL, default 300        (env: NEW_TTL)
  -d, --domain DOMAIN    test domain                 (env: TEST_DOMAIN)
  -a, --all              process ALL zones of the account (step 2)
  -n, --dry-run          only show what would be changed, do not update
  -h, --help             show this help

Examples:
  export HTTPNET_API_KEY="..."
  $(basename "$0") -i 203.0.113.10 -d example.com --dry-run
  $(basename "$0") -i 203.0.113.10 -d example.com
  $(basename "$0") -i 203.0.113.10 --all --dry-run
  $(basename "$0") -i 203.0.113.10 --all
EOF
}

# --- Argument parsing --------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -k|--api-key) API_KEY="$2"; shift 2 ;;
        -i|--ip)      TARGET_IP="$2"; shift 2 ;;
        -t|--ttl)     NEW_TTL="$2"; shift 2 ;;
        -d|--domain)  TEST_DOMAIN="$2"; shift 2 ;;
        -a|--all)     MODE="all"; shift ;;
        -n|--dry-run) DRY_RUN=1; shift ;;
        -h|--help)    usage; exit 0 ;;
        *) err "Unknown option: $1"; usage >&2; exit 1 ;;
    esac
done

# --- Checks ------------------------------------------------------------------
for cmd in curl jq; do
    command -v "$cmd" >/dev/null 2>&1 || { err "'$cmd' is required but not installed (e.g. sudo apt install $cmd)."; exit 1; }
done
[[ -z "$API_KEY"   || "$API_KEY"   == "<api-key>"   ]] && { err "No API key set (use -k or HTTPNET_API_KEY)."; exit 1; }
[[ -z "$TARGET_IP" || "$TARGET_IP" == "<server-ip>" ]] && { err "No target IP set (use -i or TARGET_IP)."; exit 1; }
[[ "$NEW_TTL" =~ ^[0-9]+$ ]] || { err "TTL must be a number of seconds."; exit 1; }
if [[ "$MODE" == "test" && ( -z "$TEST_DOMAIN" || "$TEST_DOMAIN" == "<test-domain>" ) ]]; then
    err "No test domain set (use -d or TEST_DOMAIN), or use --all."; exit 1
fi

# --- API ---------------------------------------------------------------------
# api_call <endpoint> <json-body>  -> prints JSON response, returns 1 on HTTP/curl error
api_call() {
    local endpoint="$1" body="$2" response
    if ! response=$(curl -sS --fail-with-body -X POST \
            -H "Content-Type: application/json" \
            --data-binary @- \
            "$BASE_URL/$endpoint" <<<"$body"); then
        err "API call '$endpoint' failed: $response"
        return 1
    fi
    printf '%s' "$response"
}

# find_all <endpoint> <filter-json>  -> prints a JSON array of all entries (handles pagination)
find_all() {
    local endpoint="$1" filter="$2" page=1 total_pages=1 body response all='[]'
    while (( page <= total_pages )); do
        body=$(jq -n --arg key "$API_KEY" --argjson filter "$filter" \
                     --argjson page "$page" --argjson limit "$PAGE_LIMIT" \
               '{authToken: $key, page: $page, limit: $limit}
                + (if $filter == null then {} else {filter: $filter} end)')
        response=$(api_call "$endpoint" "$body") || return 1

        if [[ "$(jq -r '.status // empty' <<<"$response")" == "error" ]]; then
            err "API returned an error for '$endpoint':"
            jq '.errors' <<<"$response" >&2
            return 1
        fi

        all=$(jq -s '.[0] + (.[1].response.data // [])' <(printf '%s' "$all") <(printf '%s' "$response"))
        total_pages=$(jq -r '.response.totalPages // 1' <<<"$response")
        page=$((page + 1))
    done
    printf '%s' "$all"
}

# get_a_records <ip> [domain-filter]  -> prints a JSON array of matching A records (with zoneName)
get_a_records() {
    local ip="$1" domain="${2:-}" zone_filter zones count result='[]'

    if [[ -n "$domain" ]]; then
        zone_filter=$(jq -n --arg v "*$domain*" '{field: "ZoneName", value: $v}')
    else
        zone_filter='null'
    fi

    zones=$(find_all "zoneConfigsFind" "$zone_filter") || return 1
    count=$(jq 'length' <<<"$zones")
    debug "Found $count zone configurations." >&2

    local zone_name zone_id rec_filter records n matched
    while IFS=$'\t' read -r zone_name zone_id; do
        [[ -z "$zone_id" ]] && continue
        debug "Fetching records for zone: $zone_name (ID: $zone_id)" >&2

        rec_filter=$(jq -n --arg v "$zone_id" '{field: "ZoneConfigId", value: $v}')
        if ! records=$(find_all "recordsFind" "$rec_filter"); then
            warn "No records found for $zone_name or error in recordsFind." >&2
            continue
        fi
        n=$(jq 'length' <<<"$records")
        debug "Found $n records in zone $zone_name." >&2

        matched=$(jq --arg ip "$ip" --arg zone "$zone_name" \
            '[ .[] | select(.type == "A" and .content == $ip) | . + {zoneName: $zone} ]' <<<"$records")
        result=$(jq -s '.[0] + .[1]' <(printf '%s' "$result") <(printf '%s' "$matched"))
    done < <(jq -r '.[] | [.name, .id] | @tsv' <<<"$zones")

    printf '%s' "$result"
}

# update_record_ttl <records-json> <ttl>
update_record_ttl() {
    local records="$1" ttl="$2" zone_name group body response status count skipped

    if [[ "$(jq 'length' <<<"$records")" -eq 0 ]]; then
        info "No records to update."
        return 0
    fi

    debug "First record properties: $(jq -r '.[0] | keys | join(", ")' <<<"$records")"

    # The API requires updates to be scoped to a zoneName
    while IFS= read -r zone_name; do
        group=$(jq --arg z "$zone_name" '[ .[] | select(.zoneName == $z) ]' <<<"$records")
        skipped=$(jq --argjson t "$ttl" '[ .[] | select(.ttl == $t) ] | length' <<<"$group")
        group=$(jq --argjson t "$ttl" '[ .[] | select(.ttl != $t) ]' <<<"$group")
        count=$(jq 'length' <<<"$group")

        info "Updating records for zone: $zone_name"
        (( skipped > 0 )) && debug "  $skipped record(s) already have TTL $ttl, skipped."
        if (( count == 0 )); then
            continue
        fi

        if (( DRY_RUN )); then
            warn "  [dry-run] would set TTL $ttl on $count record(s):"
            jq -r '.[] | "    \(.name)  A  \(.content)  (TTL \(.ttl))"' <<<"$group"
            continue
        fi

        body=$(jq -n --arg key "$API_KEY" --arg zone "$zone_name" --argjson t "$ttl" --argjson g "$group" \
            '{authToken: $key, zoneName: $zone,
              recordsToModify: [ $g[] | {id, name, type, content, ttl: $t} ]}')

        if ! response=$(api_call "recordsUpdate" "$body"); then
            err "  Failed to update records in $zone_name (API response was empty or HTTP error)."
            continue
        fi
        status=$(jq -r '.status // "unknown"' <<<"$response")

        if [[ "$status" == "success" || "$status" == "pending" ]]; then
            ok "  Successfully updated $count records in $zone_name (Status: $status)."
        else
            err "  Failed to update records in ${zone_name}: $status"
            warn "  Full Error Response: $(jq . <<<"$response")"
        fi
    done < <(jq -r '[ .[].zoneName ] | unique | .[]' <<<"$records")
}

# --- Execution ---------------------------------------------------------------
(( DRY_RUN )) && warn "*** DRY RUN - no changes will be made ***"

if [[ "$MODE" == "test" ]]; then
    info "--- Step 1: Testing with $TEST_DOMAIN ---"
    records=$(get_a_records "$TARGET_IP" "$TEST_DOMAIN")
    count=$(jq 'length' <<<"$records")
    if (( count > 0 )); then
        info "Found $count A records for $TEST_DOMAIN pointing to $TARGET_IP."
        update_record_ttl "$records" "$NEW_TTL"
    else
        info "No A records found for $TEST_DOMAIN pointing to $TARGET_IP."
    fi
else
    info "--- Step 2: Processing ALL domains for IP $TARGET_IP ---"
    records=$(get_a_records "$TARGET_IP")
    count=$(jq 'length' <<<"$records")
    if (( count > 0 )); then
        info "Found $count A records pointing to $TARGET_IP."
        update_record_ttl "$records" "$NEW_TTL"
    else
        info "No A records found pointing to $TARGET_IP."
    fi
fi
