# Install Podkop Orbit

The repository and its GitHub Releases are private. You need a fine-grained GitHub token with **Contents: read** access to `kimurraaa/podkop`. The release workflow creates installable APK/IPK packages when a version tag is pushed.

## 1. Save the token on the router

Connect to OpenWrt as root and save the token with root-only permissions:

```sh
mkdir -p /root/.config/podkop-orbit
chmod 700 /root/.config/podkop-orbit
umask 077
cat > /root/.config/podkop-orbit/github-token
```

Paste the token, press **Enter**, then **Ctrl+D**. The installer reads this file for both GitHub access and release downloads.

## 2. Install or update

Run this single command on the router:

```sh
TOKEN="$(cat /root/.config/podkop-orbit/github-token)" && wget \
  --header="Accept: application/vnd.github.raw+json" \
  --header="Authorization: Bearer $TOKEN" -qO /tmp/podkop-orbit-install.sh \
  "https://api.github.com/repos/kimurraaa/podkop/contents/install.sh?ref=podkop-orbit" && \
sh /tmp/podkop-orbit-install.sh
```

The installer updates package indexes, installs sing-box if needed, downloads the latest private release, installs Podkop Orbit and restarts its service. It supports OpenWrt `apk` and `opkg` package managers.

To publish an installable release, push a version tag from the repository, for example `0.1.1`. The private GitHub Actions workflow builds the packages and creates the release. The router needs internet access while installing; restarting Podkop can interrupt the current connection.
