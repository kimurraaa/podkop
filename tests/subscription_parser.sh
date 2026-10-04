#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PARSER="$ROOT_DIR/podkop/files/usr/lib/subscription_parser.uc"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

if ! command -v ucode >/dev/null 2>&1; then
    echo "Subscription parser checks skipped: ucode is not installed"
    exit 0
fi

cat > "$WORK_DIR/uris.txt" <<'URIS'
# sample list
vless://11111111-1111-4111-8111-111111111111@example.com:443?security=tls#Example
trojan://secret@example.net:443#Backup
URIS

ucode "$PARSER" normalize-content "$WORK_DIR/uris.txt" "$WORK_DIR/plain.json"
[ "$(jq '[.outbounds[] | select(.type == "vless" or .type == "trojan")] | length' "$WORK_DIR/plain.json")" -eq 2 ]

# Match Forkop's Base64URL normalization path, including omitted padding.
base64 -w 0 "$WORK_DIR/uris.txt" | tr '+/' '-_' | tr -d '=' > "$WORK_DIR/uris.base64url"
ucode "$PARSER" normalize-content "$WORK_DIR/uris.base64url" "$WORK_DIR/base64url.json"
[ "$(jq '[.outbounds[] | select(.type == "vless" or .type == "trojan")] | length' "$WORK_DIR/base64url.json")" -eq 2 ]

cat > "$WORK_DIR/sing-box.json" <<'JSON'
{"outbounds":[{"type":"vless","tag":"json-node","server":"example.com","server_port":443,"uuid":"11111111-1111-4111-8111-111111111111"}]}
JSON
ucode "$PARSER" normalize-content "$WORK_DIR/sing-box.json" "$WORK_DIR/json-outbounds.json"
[ "$(jq -r '.format' "$WORK_DIR/json-outbounds.json")" = "sing-box-json" ]
[ "$(jq -r '.outbounds[0].type' "$WORK_DIR/json-outbounds.json")" = "vless" ]

echo "Subscription parser checks passed"
