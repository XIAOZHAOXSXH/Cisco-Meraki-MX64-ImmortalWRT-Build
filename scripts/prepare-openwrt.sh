#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
	cat >&2 <<'EOF'
Usage: scripts/prepare-openwrt.sh OPENWRT_DIR [REPOSITORY_ROOT]

Prepare an ImmortalWrt tree with the pinned package feed, Argon branding,
and the repository rootfs overlay.
EOF
}

die() {
	echo "prepare-openwrt: error: $*" >&2
	exit 1
}

log() {
	echo "prepare-openwrt: $*"
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 2; }

OPENWRT_DIR="$(cd "$1" && pwd)"
REPOSITORY_ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPOSITORY_ROOT="$(cd "$REPOSITORY_ROOT" && pwd)"

[[ -f "$OPENWRT_DIR/scripts/feeds" ]] || die "not an ImmortalWrt tree: $OPENWRT_DIR"
[[ -f "$REPOSITORY_ROOT/sources.lock" ]] || die "missing sources.lock in $REPOSITORY_ROOT"
[[ -f "$REPOSITORY_ROOT/logo.jpg" ]] || die "missing logo.jpg in $REPOSITORY_ROOT"
[[ -f "$REPOSITORY_ROOT/patches/luci-theme-argon-branding.patch" ]] || die "missing Argon patch"
[[ -f "$REPOSITORY_ROOT/assets/argon-branding.css" ]] || die "missing Argon CSS"

# sources.lock is repository-owned data, not remote input. Keep its values in
# the environment so feed commands can use the same immutable pins.
set -a
# shellcheck disable=SC1091
. "$REPOSITORY_ROOT/sources.lock"
set +a

for required in \
	IMMORTALWRT_REPOSITORY IMMORTALWRT_BRANCH IMMORTALWRT_COMMIT \
	IMMORTALWRT_LUCI_REPOSITORY IMMORTALWRT_LUCI_BRANCH IMMORTALWRT_LUCI_COMMIT \
	KENZOK8_SMALL_REPOSITORY KENZOK8_SMALL_BRANCH KENZOK8_SMALL_COMMIT; do
	[[ -n "${!required:-}" ]] || die "sources.lock does not define $required"
done

valid_sha() {
	[[ "$1" =~ ^[0-9a-fA-F]{40}$ ]]
}

valid_sha "$IMMORTALWRT_COMMIT" || die "invalid IMMORTALWRT_COMMIT"
valid_sha "$IMMORTALWRT_LUCI_COMMIT" || die "invalid IMMORTALWRT_LUCI_COMMIT"
valid_sha "$KENZOK8_SMALL_COMMIT" || die "invalid KENZOK8_SMALL_COMMIT"

retry() {
	local attempts=3
	local try
	for ((try = 1; try <= attempts; try++)); do
		if "$@"; then
			return 0
		fi
		if (( try < attempts )); then
			log "command failed (attempt $try/$attempts); retrying in 5 seconds"
			sleep 5
		fi
	done
	return 1
}

if [[ -d "$OPENWRT_DIR/.git" ]]; then
	actual_core="$(git -C "$OPENWRT_DIR" rev-parse HEAD 2>/dev/null || true)"
	[[ "$actual_core" == "$IMMORTALWRT_COMMIT" ]] || \
		die "ImmortalWrt checkout is $actual_core, expected $IMMORTALWRT_COMMIT"
fi

FEEDS_CONF="$OPENWRT_DIR/feeds.conf"
[[ -f "$FEEDS_CONF" ]] || cp "$OPENWRT_DIR/feeds.conf.default" "$FEEDS_CONF"

pin_feed() {
	local feed_name="$1"
	local repository="$2"
	local commit="$3"
	local replacement="src-git ${feed_name} ${repository}^${commit}"
	local temporary_file

	if grep -qE "^src-git[^[:space:]]*[[:space:]]+${feed_name}([[:space:]]|$)" "$FEEDS_CONF"; then
		temporary_file="${FEEDS_CONF}.tmp.$$"
		awk -v name="$feed_name" -v line="$replacement" '
			$1 ~ /^src-git/ && $2 == name {
				if (!replaced++) print line
				next
			}
			{ print }
		' "$FEEDS_CONF" > "$temporary_file"
		mv "$temporary_file" "$FEEDS_CONF"
	else
		printf '%s\n' "$replacement" >> "$FEEDS_CONF"
	fi
}

pin_feed luci "$IMMORTALWRT_LUCI_REPOSITORY" "$IMMORTALWRT_LUCI_COMMIT"
pin_feed small "$KENZOK8_SMALL_REPOSITORY" "$KENZOK8_SMALL_COMMIT"

# The feeds script uses relative paths, so it must run from the buildroot.
cd "$OPENWRT_DIR"

log "updating feeds"
FEEDS_CMD=(perl "$OPENWRT_DIR/scripts/feeds")
retry "${FEEDS_CMD[@]}" update -a
log "installing only required feed packages"
retry "${FEEDS_CMD[@]}" install -p luci luci-theme-argon
retry "${FEEDS_CMD[@]}" install -p small luci-app-openclash
retry "${FEEDS_CMD[@]}" install -p small luci-app-passwall

SMALL_DIR="$OPENWRT_DIR/feeds/small"
[[ -d "$SMALL_DIR/.git" ]] || die "small feed was not cloned to $SMALL_DIR"
actual_small="$(git -C "$SMALL_DIR" rev-parse HEAD)"
[[ "$actual_small" == "$KENZOK8_SMALL_COMMIT" ]] || \
	die "small feed checkout is $actual_small, expected $KENZOK8_SMALL_COMMIT"

LUCI_DIR="$OPENWRT_DIR/feeds/luci"
[[ -d "$LUCI_DIR/.git" ]] || die "luci feed was not cloned to $LUCI_DIR"
actual_luci="$(git -C "$LUCI_DIR" rev-parse HEAD)"
[[ "$actual_luci" == "$IMMORTALWRT_LUCI_COMMIT" ]] || \
	die "luci feed checkout is $actual_luci, expected $IMMORTALWRT_LUCI_COMMIT"

log "staging repository overlay"
mkdir -p "$OPENWRT_DIR/files"
cp -a "$REPOSITORY_ROOT/files/." "$OPENWRT_DIR/files/"

find_package_root() {
	local package_name="$1"
	find -L "$OPENWRT_DIR/feeds" "$OPENWRT_DIR/package" \
		-type f -path "*/$package_name/Makefile" -print -quit 2>/dev/null |
		sed 's#/Makefile$##'
}

ARGON_DIR="$OPENWRT_DIR/package/feeds/luci/luci-theme-argon"
[[ -d "$ARGON_DIR" ]] || ARGON_DIR="$(find_package_root luci-theme-argon)"
[[ -n "$ARGON_DIR" && -d "$ARGON_DIR" ]] || die "luci-theme-argon was not installed"
# feeds install the package through a symlink; resolve it so patch/install
# operate on the actual Argon package directory rather than the feed repo root.
ARGON_DIR="$(cd "$ARGON_DIR" && pwd -P)"

for required_path in \
	"$ARGON_DIR/ucode/template/themes/argon/header.ut" \
	"$ARGON_DIR/ucode/template/themes/argon/header_login.ut" \
	"$ARGON_DIR/ucode/template/themes/argon/sysauth.ut" \
	"$ARGON_DIR/htdocs/luci-static/argon/img/bg1.jpg"; do
	[[ -e "$required_path" ]] || die "unexpected Argon layout; missing $required_path"
done

PATCH_FILE="$REPOSITORY_ROOT/patches/luci-theme-argon-branding.patch"
if ! grep -q 'mx64-branding.css' "$ARGON_DIR/ucode/template/themes/argon/header.ut" || \
	! grep -q 'mx64-logo.jpg' "$ARGON_DIR/ucode/template/themes/argon/sysauth.ut"; then
	if command -v patch >/dev/null 2>&1 && \
		patch --dry-run -d "$ARGON_DIR" -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
		patch -d "$ARGON_DIR" -p1 < "$PATCH_FILE"
	elif git -C "$ARGON_DIR" apply --check --no-index -p1 "$PATCH_FILE" >/dev/null 2>&1; then
		git -C "$ARGON_DIR" apply --no-index -p1 "$PATCH_FILE"
	else
		die "Argon branding patch does not apply to this source layout"
	fi
else
	log "Argon branding patch already applied"
fi

ARGON_WEB_ROOT="$ARGON_DIR/htdocs/luci-static/argon"
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$ARGON_WEB_ROOT/img/mx64-logo.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$ARGON_WEB_ROOT/img/bg1.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$ARGON_WEB_ROOT/background/mx64-login.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/assets/argon-branding.css" "$ARGON_WEB_ROOT/css/mx64-branding.css"

# Keep the same assets in the rootfs overlay. This covers images when the
# theme package is rebuilt or replaced by another feed package.
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$OPENWRT_DIR/files/www/luci-static/argon/img/mx64-logo.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$OPENWRT_DIR/files/www/luci-static/argon/img/bg1.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/logo.jpg" "$OPENWRT_DIR/files/www/luci-static/argon/background/mx64-login.jpg"
install -D -m 0644 "$REPOSITORY_ROOT/assets/argon-branding.css" "$OPENWRT_DIR/files/www/luci-static/argon/css/mx64-branding.css"

for required_package_path in \
	"$OPENWRT_DIR/package/feeds/luci/luci-theme-argon/Makefile" \
	"$OPENWRT_DIR/package/feeds/small/luci-app-openclash/Makefile" \
	"$OPENWRT_DIR/package/feeds/small/luci-app-passwall/Makefile"; do
	[[ -f "$required_package_path" ]] || \
		die "required feed package was not installed: $required_package_path"
done

grep -q 'mx64-branding.css' "$ARGON_DIR/ucode/template/themes/argon/header.ut" || \
	die "Argon header patch verification failed"
grep -q 'mx64-branding.css' "$ARGON_DIR/ucode/template/themes/argon/header_login.ut" || \
	die "Argon login header patch verification failed"
grep -q 'mx64-logo.jpg' "$ARGON_DIR/ucode/template/themes/argon/sysauth.ut" || \
	die "Argon login logo patch verification failed"

log "feed and Argon preparation complete"
