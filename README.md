# Podkop Orbit

Podkop Orbit is an extension of Podkop that adds subscription management to proxy sections. It keeps Podkop's routing flow and adds automatic fastest-node or manual selection, with subscription refresh every 12 hours by default.

The repository is private. Installation requires a read-only GitHub token and a release created from a version tag. See the [short install guide](docs/install-podkop-orbit.md).

```sh
TOKEN="$(cat /root/.config/podkop-orbit/github-token)" && \
wget --header="Accept: application/vnd.github.raw+json" \
  --header="Authorization: Bearer $TOKEN" -qO /tmp/podkop-orbit-install.sh \
  "https://api.github.com/repos/kimurraaa/podkop/contents/install.sh?ref=podkop-orbit" && \
sh /tmp/podkop-orbit-install.sh
```
