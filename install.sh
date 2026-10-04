#!/bin/sh
# One-command installer for Podkop Orbit GitHub Releases.
set -eu

REPOSITORY="kimurraaa/podkop"
RELEASE_API="https://api.github.com/repos/$REPOSITORY/releases/latest"
TOKEN_FILE="/root/.config/podkop-orbit/github-token"

msg() {
    printf '%s\n' "$1"
}

if [ "$(id -u)" -ne 0 ]; then
    msg "Run this installer as root."
    exit 1
fi

if command -v apk >/dev/null 2>&1; then
    PACKAGE_MANAGER="apk"
    PACKAGE_EXTENSION="apk"
elif command -v opkg >/dev/null 2>&1; then
    PACKAGE_MANAGER="opkg"
    PACKAGE_EXTENSION="ipk"
else
    msg "Neither apk nor opkg was found."
    exit 1
fi

GITHUB_TOKEN=${GITHUB_TOKEN:-}
if [ -z "$GITHUB_TOKEN" ] && [ -r "$TOKEN_FILE" ]; then
    GITHUB_TOKEN=$(cat "$TOKEN_FILE")
fi
if [ -z "$GITHUB_TOKEN" ]; then
    msg "The private repository needs a read-only GitHub token. See docs/install-podkop-orbit.md."
    exit 1
fi

TMP_DIR=$(mktemp -d /tmp/podkop-orbit-install.XXXXXX)
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM
AUTH_CONFIG="$TMP_DIR/github.curl"
RELEASE_JSON="$TMP_DIR/release.json"
chmod 700 "$TMP_DIR"
printf 'header = "Authorization: Bearer %s"\n' "$GITHUB_TOKEN" > "$AUTH_CONFIG"
chmod 600 "$AUTH_CONFIG"
unset GITHUB_TOKEN

if [ "$PACKAGE_MANAGER" = "apk" ]; then
    apk update
    apk add curl jq
    if ! command -v sing-box >/dev/null 2>&1; then
        apk add sing-box
    fi
else
    opkg update
    opkg install curl jq
    if ! command -v sing-box >/dev/null 2>&1; then
        opkg install sing-box
    fi
fi

msg "Fetching the latest private Podkop Orbit release..."
if ! curl -fsSL --config "$AUTH_CONFIG" \
    -H 'Accept: application/vnd.github+json' "$RELEASE_API" -o "$RELEASE_JSON"; then
    msg "Could not read the latest release. Check the token and create a version-tagged release first."
    exit 1
fi

for package in podkop-orbit luci-app-podkop-orbit luci-i18n-podkop-orbit-ru; do
    asset_url=$(jq -r --arg prefix "$package-" --arg suffix ".$PACKAGE_EXTENSION" \
        '.assets[]? | select(.name | startswith($prefix) and endswith($suffix)) | .browser_download_url' \
        "$RELEASE_JSON" | head -n 1)
    if [ -z "$asset_url" ]; then
        msg "The latest release is missing the $package.$PACKAGE_EXTENSION package."
        exit 1
    fi
    msg "Downloading $package.$PACKAGE_EXTENSION..."
    curl -fsSL --config "$AUTH_CONFIG" "$asset_url" -o "$TMP_DIR/$package.$PACKAGE_EXTENSION"
done

if [ "$PACKAGE_MANAGER" = "apk" ]; then
    apk add --allow-untrusted \
        "$TMP_DIR/podkop-orbit.apk" \
        "$TMP_DIR/luci-app-podkop-orbit.apk" \
        "$TMP_DIR/luci-i18n-podkop-orbit-ru.apk"
else
    opkg install \
        "$TMP_DIR/podkop-orbit.ipk" \
        "$TMP_DIR/luci-app-podkop-orbit.ipk" \
        "$TMP_DIR/luci-i18n-podkop-orbit-ru.ipk"
fi

/etc/init.d/podkop enable
/etc/init.d/podkop restart
msg "Podkop Orbit is installed. Open Services → Podkop Orbit in LuCI."
