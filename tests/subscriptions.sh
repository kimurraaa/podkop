#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

mkdir -p "$WORK_DIR/bin"
cat > "$WORK_DIR/bin/curl" <<'CURL'
#!/bin/sh
if [ "${SUBSCRIPTION_CURL_FAIL:-0}" = "1" ]; then
    exit 22
fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
        cp "$SUBSCRIPTION_FIXTURE" "$2"
        exit 0
    fi
    shift
done
exit 2
CURL
cat > "$WORK_DIR/bin/ucode" <<'UCODE'
#!/bin/sh
case "$2" in
    normalized-skipped-warning) exit 1 ;;
    normalize-content-validated)
        [ "${SUBSCRIPTION_NORMALIZE_FAIL:-0}" = "1" ] && exit 1
        cp "$SUBSCRIPTION_OUTBOUNDS_FIXTURE" "$4"
        exit 0
        ;;
    *) exit 2 ;;
esac
UCODE
chmod +x "$WORK_DIR/bin/curl" "$WORK_DIR/bin/ucode"

export PATH="$WORK_DIR/bin:$PATH"
export TMP_SING_BOX_FOLDER="$WORK_DIR/runtime"
export PODKOP_LIB="$ROOT_DIR/podkop/files/usr/lib"
log() { :; }
. "$ROOT_DIR/podkop/files/usr/lib/subscriptions.sh"

cat > "$WORK_DIR/outbounds.json" <<'JSON'
{
  "version": 1,
  "format": "sing-box-json",
  "outbounds": [
    { "type": "vless", "tag": "node-a", "server": "a.example", "share_link": "vless://example", "remark": "A" },
    { "type": "shadowsocks", "server": "b.example" },
    { "type": "selector", "tag": "provider-selector", "outbounds": [ "node-a", "node-b" ] },
    { "type": "direct", "tag": "direct" }
  ]
}
JSON
cp "$WORK_DIR/outbounds.json" "$WORK_DIR/changed.json"
sed -i 's/b.example/new.example/' "$WORK_DIR/changed.json"
printf 'raw subscription fixture\n' > "$WORK_DIR/body.txt"
export SUBSCRIPTION_FIXTURE="$WORK_DIR/body.txt"
export SUBSCRIPTION_OUTBOUNDS_FIXTURE="$WORK_DIR/outbounds.json"

outbounds_file="$(subscription_get_outbounds proxy https://example.test/sub)"
[ -s "$outbounds_file" ] || { echo "normalized subscription was not cached" >&2; exit 1; }
[ "$(jq '[.outbounds[] | select(.type == "vless" or .type == "shadowsocks")] | length' "$outbounds_file")" -eq 2 ] || {
    echo "normalized subscription did not preserve proxy outbounds" >&2
    exit 1
}
[ ! -f "$TMP_SING_BOX_FOLDER/subscriptions/proxy.changed" ] || {
    echo "first subscription fetch was marked changed" >&2
    exit 1
}

# Exercise group generation using the normalized outbound JSON from the parser.
sed -n '/^sing_box_cf_add_subscription_outbounds() {/,/^}/p' \
    "$ROOT_DIR/podkop/files/usr/lib/sing_box_config_facade.sh" > "$WORK_DIR/subscription-outbounds.sh"
get_outbound_tag_by_section() { printf '%s-out' "$1"; }
comma_string_to_json_array() {
    local IFS=,
    set -- $1
    local result='[' item separator=
    for item in "$@"; do
        result="$result$separator\"$item\""
        separator=,
    done
    printf '%s]' "$result"
}
sing_box_cm_add_raw_outbound() { printf '%s|node=%s|json=%s' "$1" "$2" "$3"; }
sing_box_cm_add_urltest_outbound() { printf '%s|urltest=%s|nodes=%s' "$1" "$2" "$3"; }
sing_box_cm_add_selector_outbound() { printf '%s|selector=%s|default=%s|choices=%s' "$1" "$2" "$4" "$3"; }
. "$WORK_DIR/subscription-outbounds.sh"

generated="$(sing_box_cf_add_subscription_outbounds '{}' sample "$outbounds_file" urltest 0)"
case "$generated" in *'node=sample-1-out'*'node=sample-2-out'*'urltest=sample-urltest-out'*'selector=sample-out'*'default=sample-urltest-out'*) ;;
    *) echo "fastest mode did not build URLTest and selector from normalized outbounds" >&2; exit 1 ;;
esac
case "$generated" in *'node=sample-3-out'*|*'provider-selector'*) echo "group or direct outbound leaked into node choices" >&2; exit 1 ;; esac
case "$generated" in *'share_link'*|*'remark'*) echo "parser-only fields leaked into the sing-box outbound" >&2; exit 1 ;; esac

generated="$(sing_box_cf_add_subscription_outbounds '{}' sample "$outbounds_file" selector 0)"
case "$generated" in *'default=sample-1-out'*) ;;
    *) echo "manual mode did not default to a concrete node" >&2; exit 1 ;;
esac
generated="$(sing_box_cf_add_subscription_outbounds '{}' sample "$outbounds_file" selector 1)"
case "$generated" in *'udp_over_tcp'*'"version":2'*) ;;
    *) echo "section UDP-over-TCP setting was not applied to Shadowsocks" >&2; exit 1 ;;
esac

export SUBSCRIPTION_OUTBOUNDS_FIXTURE="$WORK_DIR/changed.json"
outbounds_file="$(subscription_get_outbounds proxy https://example.test/sub)"
[ -f "$TMP_SING_BOX_FOLDER/subscriptions/proxy.changed" ] || {
    echo "changed subscription was not detected" >&2
    exit 1
}

export SUBSCRIPTION_CURL_FAIL=1
cached_file="$(subscription_get_outbounds proxy https://example.test/sub)"
[ "$cached_file" = "$outbounds_file" ] || { echo "last working subscription cache was not reused" >&2; exit 1; }

export SUBSCRIPTION_CURL_FAIL=0
export SUBSCRIPTION_NORMALIZE_FAIL=1
cached_file="$(subscription_get_outbounds proxy https://example.test/sub)"
[ "$cached_file" = "$outbounds_file" ] || { echo "invalid subscription replaced the last working cache" >&2; exit 1; }

echo "Subscription tests passed"
