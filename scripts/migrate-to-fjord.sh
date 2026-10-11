#!/bin/bash
# Moves Lookout's data, preferences, Keychain items and Claude Code setup over to Fjord Computer, once, on the owner's
# machine (there are no other users, so the app itself migrates nothing). Run it after installing Fjord Computer and
# before launching it. Safe to re-run: what is already done is skipped, and nothing at the new place is overwritten.
# --dry-run says what it would do and changes nothing.
set -euo pipefail

DRY=false
case "${1:-}" in
  "") ;;
  --dry-run) DRY=true ;;
  *) echo "Usage: $0 [--dry-run]" >&2; exit 2 ;;
esac

OLD_ID=dev.polarzero.lookout
NEW_ID=com.amontlabs.fjord
NEW_APP="/Applications/Fjord Computer.app"
SUPPORT="$HOME/Library/Application Support"
OLD_DATA="$SUPPORT/Lookout"
NEW_DATA="$SUPPORT/Fjord Computer"
CLAUDE_DIR="$HOME/.claude"
PY=/usr/bin/python3

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die() { printf 'Stopped: %s\n' "$*" >&2; exit 1; }
# Runs a command, or in a dry run only prints it.
run() {
  if $DRY; then printf '  would run:'; printf ' %q' "$@"; printf '\n'; else "$@"; fi
}

$DRY && say "Dry run: nothing is changed."

step "1. Apps running"
running=""
pgrep -x Lookout >/dev/null && running="Lookout"
pgrep -x FjordComputer >/dev/null && running="${running:+$running and }Fjord Computer"
if [ -z "$running" ]; then
  say "Neither Lookout nor Fjord Computer is running."
elif $DRY; then
  say "$running is running: a real run would stop here until you quit it."
else
  die "$running is running. Quit it (menu bar icon › Quit) and run this again."
fi

step "2. Data folder"
# The Router's plugin files are made again by the new app when the Router is on at launch (Router.swift startRouter →
# applyRouterSwitch(install: false) → switchPluginNow → ClaudePlugin.write, which creates plugin-sessions and relay,
# and ClaudePlugin.ensureKey, which makes relay.key). They go before the move so a re-run never touches the new app's
# own. claude-plugin is removed in step 5, after Claude Code has dropped the marketplace that points at it.
if [ -d "$OLD_DATA" ] && [ -e "$NEW_DATA" ]; then
  die "both \"$OLD_DATA\" and \"$NEW_DATA\" exist. Merge them by hand (or remove one), then run this again."
elif [ -d "$OLD_DATA" ]; then
  for name in plugin-sessions relay relay.key; do
    if [ -e "$OLD_DATA/$name" ]; then say "Removing the old $name (the new app makes its own)."; run rm -rf "$OLD_DATA/$name"; fi
  done
  say "Moving \"$OLD_DATA\" to \"$NEW_DATA\"."
  run mv "$OLD_DATA" "$NEW_DATA"
elif [ -d "$NEW_DATA" ]; then
  say "Already moved."
else
  say "No Lookout data folder; nothing to move."
fi

step "3. Preferences"
if ! defaults read "$OLD_ID" >/dev/null 2>&1; then
  say "No $OLD_ID preferences; nothing to copy."
elif defaults read "$NEW_ID" >/dev/null 2>&1; then
  # Not overwritten, and the old ones are kept so nothing is lost: the owner decides.
  say "$NEW_ID already has preferences: left as they are, and $OLD_ID kept."
  say "Once you're sure they aren't needed: defaults delete $OLD_ID"
else
  say "Copying $OLD_ID to $NEW_ID, then removing $OLD_ID."
  if $DRY; then tmp=/tmp/fjord-migrate.XXXXXX; else tmp=$(mktemp -d /tmp/fjord-migrate.XXXXXX); fi
  run defaults export "$OLD_ID" "$tmp/prefs.plist"
  run defaults import "$NEW_ID" "$tmp/prefs.plist"
  run defaults delete "$OLD_ID"
  $DRY || rm -rf "$tmp"
fi

step "4. Keychain"
# The secret is read into a variable (command substitution, never on a command line) and handed to `security -i` on
# its stdin, so it doesn't show in `ps`. That needs it quoted for security's own parser, so only plain token characters
# are accepted; anything else falls back to `-w <secret>` on the command line, briefly visible to `ps` on this machine.
# The copy is read back and compared before the old item goes. macOS asks once to let `security` read the old item,
# and Fjord Computer may still ask once when it first reads the new one.
has_item() { security find-generic-password -s "$1" -a "$2" >/dev/null 2>&1; }
for account in github-token typesafe-key; do
  if ! has_item "$OLD_ID" "$account"; then
    say "$account: nothing under $OLD_ID."
  elif has_item "$NEW_ID" "$account"; then
    say "$account: already under $NEW_ID; the old item is kept."
    say "  Once you're sure it isn't needed: security delete-generic-password -s $OLD_ID -a $account"
  elif $DRY; then
    say "$account: would copy it to $NEW_ID (readable by \"$NEW_APP\") and delete the old item."
    [ -d "$NEW_APP" ] || say "  (\"$NEW_APP\" isn't installed: a real run would stop here until it is.)"
  elif [ ! -d "$NEW_APP" ]; then
    die "\"$NEW_APP\" isn't installed: install it first (its Keychain items are made readable by it)."
  else
    say "$account: copying it to $NEW_ID (allow \"security\" if macOS asks)."
    # Byte for byte: the "x" keeps any trailing newline the value has from $(…), and only the one `-w` adds goes.
    secret=$(security find-generic-password -s "$OLD_ID" -a "$account" -w && printf x) || die "couldn't read $account under $OLD_ID."
    secret=${secret%x}; secret=${secret%$'\n'}
    [ -n "$secret" ] || die "$account under $OLD_ID is empty."
    case "$secret" in
      *[!A-Za-z0-9_.~+/=-]*)
        say "  (unusual characters: passing it on the command line)"
        security add-generic-password -s "$NEW_ID" -a "$account" -w "$secret" -T "$NEW_APP" ;;
      *)
        printf 'add-generic-password -s %s -a %s -w "%s" -T "%s"\n' "$NEW_ID" "$account" "$secret" "$NEW_APP" \
          | security -i >/dev/null ;;
    esac || die "couldn't add $account under $NEW_ID."
    copied=$(security find-generic-password -s "$NEW_ID" -a "$account" -w 2>/dev/null && printf x || true)
    copied=${copied%x}; copied=${copied%$'\n'}
    if [ "$copied" != "$secret" ]; then
      security delete-generic-password -s "$NEW_ID" -a "$account" >/dev/null 2>&1 || true
      die "the copy of $account under $NEW_ID didn't read back the same; removed it, the old item is untouched."
    fi
    unset secret copied
    security delete-generic-password -s "$OLD_ID" -a "$account" >/dev/null || die "couldn't delete $account under $OLD_ID."
    say "  Done."
  fi
done

step "5. Claude Code"
# Lookout's form hook entry, exactly as FormHookInstaller.uninstall takes it out (Forms.swift): from
# hooks.PermissionRequest, every hook whose command is the script's path (or that path shell-quoted); an entry left
# with no hook goes, then an empty PermissionRequest, then an empty hooks. The file is written in the format the app
# and Claude Code use (2 spaces, " : "), keys in their order, so only that entry changes; through a symlink to its target.
SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_SCRIPT="$CLAUDE_DIR/hooks/lookout-form.sh"
if [ -e "$SETTINGS" ]; then
  [ -x "$PY" ] || die "$PY isn't there (install the Xcode Command Line Tools: xcode-select --install)."
  dry=0; $DRY && dry=1
  "$PY" -I - "$SETTINGS" "$HOOK_SCRIPT" "$dry" <<'PY'
import json, os, sys, tempfile
path, script, dry = os.path.realpath(sys.argv[1]), sys.argv[2], sys.argv[3] == "1"
quoted = "'" + script.replace("'", "'\\''") + "'"
raw = open(path, "rb").read()
try:
    root = json.loads(raw)
except ValueError:
    sys.exit("Stopped: %s isn't valid JSON; fix it and run this again." % sys.argv[1])
if not isinstance(root, dict):
    sys.exit("Stopped: %s doesn't hold a JSON object." % sys.argv[1])
def is_us(h):
    return isinstance(h, dict) and h.get("command") in (script, quoted)
hooks = root.get("hooks")
entries = hooks.get("PermissionRequest") if isinstance(hooks, dict) else None
if not isinstance(entries, list) or not any(
        isinstance(e, dict) and isinstance(e.get("hooks"), list) and any(map(is_us, e["hooks"])) for e in entries):
    print("No Lookout form hook in %s." % sys.argv[1])
    sys.exit(0)
kept = []
for e in entries:
    if isinstance(e, dict) and isinstance(e.get("hooks"), list):
        others = [h for h in e["hooks"] if not is_us(h)]
        if len(others) != len(e["hooks"]):
            if not others:
                continue
            e = dict(e, hooks=others)
    kept.append(e)
if kept: hooks["PermissionRequest"] = kept
else: del hooks["PermissionRequest"]
if not hooks: del root["hooks"]
def dump(obj): return (json.dumps(obj, indent=2, separators=(",", " : "), ensure_ascii=False) + "\n").encode()
if dump(json.loads(raw)) != raw:
    print("(%s wasn't in the app's format: it is rewritten in it, same content.)" % sys.argv[1])
if dry:
    print("Would remove Lookout's form hook from %s." % sys.argv[1])
    sys.exit(0)
mode = os.stat(path).st_mode & 0o7777
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".settings.json.")
try:
    with os.fdopen(fd, "wb") as f:
        f.write(dump(root))
    os.chmod(tmp, mode)
    if open(path, "rb").read() != raw:
        sys.exit("Stopped: %s changed while it was being edited; run this again." % sys.argv[1])
    os.replace(tmp, path)
except BaseException:
    if os.path.exists(tmp): os.unlink(tmp)
    raise
print("Removed Lookout's form hook from %s." % sys.argv[1])
PY
else
  say "No $SETTINGS."
fi
for f in "$HOOK_SCRIPT" "$SETTINGS.lookout-backup"; do
  if [ -e "$f" ]; then say "Removing $f."; run rm -f "$f"; fi
done

# The plugin, as ClaudePluginInstaller.uninstall does it (ClaudePlugin.swift): with Claude Code's binary the Claude app
# bundles (RouterStatus.findDefault: the highest <version>/<hash>/claude.app under its claude-code folder), run in a clean
# environment, and only for what `plugin list` / `plugin marketplace list` still show.
find_claude() {
  local root="$SUPPORT/Claude/claude-code" version
  [ -d "$root" ] || return 1
  local dir bin
  for version in $(for dir in "$root"/[0-9]*/; do [ -d "$dir" ] && basename "$dir"; done | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
    for bin in "$root/$version"/*/claude.app/Contents/MacOS/claude; do
      if [ -x "$bin" ]; then printf '%s\n' "$bin"; return 0; fi
    done
  done
  return 1
}
claude() {
  /usr/bin/env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin LANG=en_US.UTF-8 USER="${USER:-}" TMPDIR="${TMPDIR:-/tmp}" \
    "$CLAUDE" "$@"
}
# Whether a `--json` list holds an item whose `key` is `value`: 0 yes, 1 no, 2 when the list can't be read.
lists() {
  "$PY" -I -c '
import json, sys
try:
    items = json.load(sys.stdin)
    if not isinstance(items, list) or not all(isinstance(i, dict) for i in items):
        sys.exit(2)
    found = any(i.get(sys.argv[1]) == sys.argv[2] for i in items)
except Exception:
    sys.exit(2)
sys.exit(0 if found else 1)' "$1" "$2"
}
plugin_gone=false
if CLAUDE=$(find_claude); then
  say "Claude Code: $CLAUDE"
  out=$(claude plugin list --json) || die "\`claude plugin list --json\` failed."
  if printf '%s' "$out" | lists id lookout@lookout; then
    say "Uninstalling the lookout@lookout plugin."
    run claude plugin uninstall lookout@lookout --scope user
  else
    [ $? -eq 1 ] || die "couldn't read \`claude plugin list --json\`'s answer."
    say "The lookout@lookout plugin isn't installed."
  fi
  out=$(claude plugin marketplace list --json) || die "\`claude plugin marketplace list --json\` failed."
  if printf '%s' "$out" | lists name lookout; then
    say "Removing the lookout marketplace."
    run claude plugin marketplace remove lookout
  else
    [ $? -eq 1 ] || die "couldn't read \`claude plugin marketplace list --json\`'s answer."
    say "The lookout marketplace isn't there."
  fi
  plugin_gone=true
else
  say "Claude Code (the copy the Claude app bundles) wasn't found: the lookout@lookout plugin and the lookout"
  say "marketplace, if still there, have to go by hand (/plugin in Claude Code)."
fi
# The old plugin's folder, moved with the data: only Lookout's (its manifest names it "lookout"), never the new app's.
OLD_PLUGIN="$NEW_DATA/claude-plugin"
$DRY && [ ! -d "$NEW_DATA" ] && OLD_PLUGIN="$OLD_DATA/claude-plugin"  # not moved in a dry run
if $plugin_gone && [ -f "$OLD_PLUGIN/.claude-plugin/plugin.json" ] \
    && "$PY" -I -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("name") == "lookout" else 1)' \
         "$OLD_PLUGIN/.claude-plugin/plugin.json"; then
  say "Removing the old plugin's folder (the new app writes its own)."
  run rm -rf "$OLD_PLUGIN"
fi

step "6. Caches"
CACHE="$HOME/Library/Caches/$OLD_ID"
if [ -e "$CACHE" ]; then say "Removing $CACHE."; run rm -rf "$CACHE"; else say "No old cache."; fi

step "Left to you"
say "- Remove /Applications/Lookout.app, and Lookout from System Settings › General › Login Items."
say "- Open Fjord Computer. With the Router on, it installs its fjord@fjord plugin at launch, but not its form hook"
say "  (at launch it only re-installs a hook that is outdated, not one that is missing): switch the Router off and"
say "  on once in Settings to install it."
say "- Claude Code sessions already open keep the old plugin until they restart (or /reload-plugins)."
$DRY && say "(Dry run: nothing was changed.)"
say "Done."
