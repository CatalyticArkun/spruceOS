#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
. "$SCRIPT_DIR/lib/common.sh"

ZIP="$SD_ROOT/bundle_update.zip"
WORK="$SCRIPT_DIR/.update_work"
STAGE="$WORK/stage"
LOG="$DIAG_ROOT/update.log"

log() {
  echo "$(timestamp_utc) $*" >> "$LOG"
}

if [ ! -f "$ZIP" ]; then
  log "No update zip at $ZIP"
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$STAGE"
unzip -oq "$ZIP" -d "$STAGE"

[ -f "$STAGE/diagnostics_bundle/bundle_version.txt" ] || { log "Invalid zip structure"; exit 1; }

NEW_VERSION=$(tr -d '[:space:]' < "$STAGE/diagnostics_bundle/bundle_version.txt")
CUR_VERSION=$(get_bundle_version)

case "$NEW_VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) log "Invalid SemVer in bundle_version.txt: $NEW_VERSION"; exit 1 ;;
esac

if [ "$NEW_VERSION" = "$CUR_VERSION" ]; then
  log "Refusing update: version unchanged ($CUR_VERSION)"
  exit 1
fi
log "Starting update $CUR_VERSION -> $NEW_VERSION"

NEW_DIR="$SPRUCE_ROOT/scripts/diagnostics.new"
BACKUP_DIR="$SPRUCE_ROOT/scripts/diagnostics.backup"

rm -rf "$NEW_DIR" "$BACKUP_DIR"
cp -a "$SPRUCE_ROOT/scripts/diagnostics" "$BACKUP_DIR"
cp -a "$STAGE/diagnostics_bundle/scripts/diagnostics" "$NEW_DIR"

if [ ! -f "$NEW_DIR/runner.sh" ]; then
  log "Validation failed: runner.sh missing"
  rm -rf "$NEW_DIR"
  exit 1
fi

rm -rf "$SPRUCE_ROOT/scripts/diagnostics"
mv "$NEW_DIR" "$SPRUCE_ROOT/scripts/diagnostics"

if [ ! -f "$SPRUCE_ROOT/scripts/diagnostics/runner.sh" ]; then
  log "Swap failed, rolling back"
  rm -rf "$SPRUCE_ROOT/scripts/diagnostics"
  mv "$BACKUP_DIR" "$SPRUCE_ROOT/scripts/diagnostics"
  exit 1
fi

rm -rf "$BACKUP_DIR" "$WORK"
log "Update successful to $NEW_VERSION"
