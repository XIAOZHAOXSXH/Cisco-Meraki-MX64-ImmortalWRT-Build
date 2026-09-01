# Cisco Meraki MX64 ImmortalWrt Build

This repository builds an ImmortalWrt image for the Cisco Meraki MX64 using
the `bcm53xx/generic` target. Argon is selected as the default LuCI theme,
and the image includes `luci-app-openclash` and `luci-app-passwall` from the
pinned [`kenzok8/small`](https://github.com/kenzok8/small) feed.

## Hardware boundary

The workflow targets the regular MX64 device definition:

```text
bcm53xx/generic/meraki_mx64
```

It is **not** for the MX64 A0 hardware variant. Check the device label or
serial information before flashing. The A0 image uses a different device-tree
configuration and must not be mixed with this image.

## Branding

The repository-root `logo.jpg` is copied into Argon as the header logo and as
the login-page background. The preparation script also installs it in Argon's
`background/` directory so the login page remains branded when Argon's local
background selection is enabled.

## GitHub Actions

The workflow in `.github/workflows/build-immortalwrt-mx64.yml` runs on pushes
to `main`, on the monthly schedule, or manually with **Run workflow**. It:

1. Checks out the immutable ImmortalWrt and package-feed commits in
   `sources.lock`.
2. Installs feeds and applies the MX64 configuration and Argon branding.
3. Runs `make defconfig`, verifies the target and required packages, and
   compiles the firmware.
4. Uploads a run artifact and publishes a run-specific GitHub Release.

Each successful release contains the MX64 `sysupgrade` image, a `SHA256SUMS`
file, the generated configuration, and the upstream target checksums when
available. Use the `sysupgrade` asset intended for `meraki_mx64`; do not use an
A0 image.

The Actions runner uses its own network. It cannot reach a proxy listening on
your workstation's `127.0.0.1:7890`; that proxy is useful only for local Git
operations such as the initial push.

## Sources and maintenance

`sources.lock` records the exact ImmortalWrt core, LuCI, and `kenzok8/small`
commits. The feed supplies both requested LuCI applications and their package
dependencies. To update a source, change its URL/branch/commit together, run
the static checks, and inspect the resulting build before publishing.

The local preparation entry point is:

```bash
bash scripts/prepare-openwrt.sh /path/to/immortalwrt /path/to/this-repository
```

It fails early if a feed, Argon template, required package, or branding asset
is missing. No GitHub token or device credential belongs in this repository.
