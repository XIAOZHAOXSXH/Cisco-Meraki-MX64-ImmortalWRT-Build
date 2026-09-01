# Cisco Meraki MX64 ImmortalWrt Build Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and publish an ImmortalWrt firmware image for the Cisco Meraki MX64 with Argon as the default LuCI theme, PassWall and OpenClash included, and the supplied Xtreme Link image applied to Argon branding and its login background.

**Architecture:** A repository-owned GitHub Actions workflow checks out a pinned ImmortalWrt release branch, adds the maintained package feeds, stages a board-specific OpenWrt configuration, then verifies required package selections before compiling. A preparation script validates the upstream Argon layout and replaces only its documented branding assets; it fails rather than silently producing an unbranded image if an upstream layout changes. The workflow uploads both a build artifact and the generated `sysupgrade` image to a uniquely tagged GitHub Release.

**Tech Stack:** GitHub Actions, ImmortalWrt `openwrt-24.10`, POSIX shell, OpenWrt feeds/Kconfig, LuCI Argon, GitHub CLI.

---

## Design decisions

- Target the non-A0 MX64 device (`bcm53xx/generic`, `meraki_mx64`). The A0 is a separate device definition and must not use this firmware.
- Default to ImmortalWrt `openwrt-24.10` because it has the verified MX64 device symbol and is a mature plugin target. The exact source commit and feed commit are recorded in `sources.lock`.
- Use the user-supplied `logo.jpg` directly as the Argon header/login logo and as both the default and selectable login background. A CSS overlay controls sizing without changing the image format or MIME type.
- Use the user-selected `https://github.com/kenzok8/small` feed for both requested applications and their companion packages. The feed is added with its immutable commit pin and checked before compilation.
- Fail before compilation if the target, Argon assets, or required LuCI application packages cannot be resolved. This makes an upstream feed break visible instead of releasing a partial firmware.

## Task 1: Add immutable repository inputs and configuration

**Files:**
- Create: `config/mx64.config`
- Create: `assets/argon-branding.css`
- Create: `files/etc/config/argon`
- Create: `files/etc/uci-defaults/99-mx64-argon-branding`
- Modify: `logo.jpg` (tracked unchanged)

**Step 1: Add the non-A0 MX64 Kconfig selections**

Set `CONFIG_TARGET_bcm53xx=y`, `CONFIG_TARGET_bcm53xx_generic=y`, and `CONFIG_TARGET_bcm53xx_generic_DEVICE_meraki_mx64=y`, then include LuCI HTTPS, Argon, OpenClash, and PassWall package selections.

**Step 2: Add first-boot Argon selection**

Write a self-deleting UCI-defaults shell script that commits `/luci-static/argon` as `luci.main.mediaurlbase`.

**Step 3: Add the Argon branding overlay**

Add CSS that sizes the supplied JPEG in the header and login form, and copy the
same JPEG into Argon's `img/` and `background/` directories.

**Step 4: Verify static inputs**

Run: `git diff --check`

Expected: no whitespace errors.

## Task 2: Implement deterministic source/feed and theme preparation

**Files:**
- Create: `scripts/prepare-openwrt.sh`

**Step 1: Add feeds idempotently**

Add the pinned `kenzok8/small` feed, update all feeds, and install the feed
package metadata so Kconfig can resolve the requested applications and their
dependencies.

**Step 2: Stage the root filesystem overlay**

Copy `files/` into the ImmortalWrt tree and install the supplied `logo.jpg` as
Argon's header logo, `bg1.jpg`, and a selectable login background.

**Step 3: Replace branding only after layout checks**

Locate the installed `luci-theme-argon`, require its expected template layout,
apply the checked unified diff, and verify all branded assets.

**Step 4: Verify required packages are discoverable**

Require both `luci-app-openclash` and `luci-app-passwall` Makefiles after feed installation. Exit nonzero with an actionable message if either is absent.

**Step 5: Syntax-check the script**

Run: `bash -n scripts/prepare-openwrt.sh`

Expected: exit code 0.

## Task 3: Create the GitHub Actions build-and-release workflow

**Files:**
- Create: `.github/workflows/build-immortalwrt-mx64.yml`

**Step 1: Define safe triggers and permissions**

Use `workflow_dispatch`, push-to-default-branch, and monthly scheduled runs. Grant only `contents: write` needed for Release publication.

**Step 2: Build in checked source**

Check out the build repository, clone the selected ImmortalWrt branch, run preparation, apply `config/mx64.config`, invoke `make defconfig`, and assert all target/package config lines survived.

**Step 3: Compile with failure diagnostics**

Download sources in parallel, compile in parallel, retry serially with verbose output only if the parallel build fails, then identify the MX64 non-A0 `sysupgrade` binary explicitly.

**Step 4: Publish outputs**

Upload a run artifact and create/update a run-specific GitHub Release using `gh`, attaching checksums plus the verified sysupgrade image.

**Step 5: Validate workflow structure**

Run YAML parsing and check all local action/script paths referenced by the workflow exist.

## Task 4: Document operation and recovery

**Files:**
- Create: `README.md`

**Step 1: Document hardware boundary and flashing artifact**

State that the release image is for MX64 only, never MX64 A0; identify the expected `sysupgrade.bin` asset.

**Step 2: Document feed provenance**

Record the selected `kenzok8/small` feed commit and explain how to update the
source lock after validating a replacement.

**Step 3: Document manual Actions operation**

Describe `workflow_dispatch`, branch selection, artifacts, releases, and what happens if preflight stops the workflow.

## Task 5: Verify, commit, push, and observe the cloud build

**Files:**
- Modify: all repository files above

**Step 1: Run local static verification**

Run shell syntax checking, UCI-default script syntax checking, YAML parsing, required-path checks, and `git diff --check`.

**Step 2: Initialize/verify Git safely**

Because the current directory is not a repository and the remote has no refs, initialize `main`, set the provided local repository identity, add the empty remote, and inspect the staged diff.

**Step 3: Commit and push**

Create one descriptive commit and push `main` using the user-authorized temporary Clash proxy only if direct access fails.

**Step 4: Confirm Actions launch and monitor result**

Use the GitHub API/CLI to confirm the push-created workflow run. On success, verify the Release includes the firmware and checksum; on a build failure, report the exact failing preflight/build stage without masking it.
