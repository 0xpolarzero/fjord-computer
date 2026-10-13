#!/bin/bash
# Moves Lookout's or Fjord's data, preferences, Keychain items and Claude Code setup over to Fjord, once, on the
# owner's machine (there are no other users, so the app itself migrates nothing). Run it after installing Fjord and
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
OLD_LOOKOUT_APP="/Applications/Lookout.app"
OLD_COMPUTER_APP="/Applications/Fjord Computer.app"
NEW_APP="/Applications/Fjord.app"
SUPPORT="$HOME/Library/Application Support"
LOOKOUT_DATA="$SUPPORT/Lookout"
COMPUTER_DATA="$SUPPORT/Fjord Computer"
NEW_DATA="$SUPPORT/Fjord"
SOURCE_DATA=""
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
pgrep -x Fjord >/dev/null && running="${running:+$running and }Fjord"
if [ -z "$running" ]; then
  say "None of Lookout, Fjord Computer and Fjord is running."
elif $DRY; then
  say "$running is running: a real run would stop here until you quit it."
else
  die "$running is running. Quit it (menu bar icon › Quit) and run this again."
fi

step "2. Data folder"
# The Router's plugin files are made again by the new app when the Router is on at launch (Router.swift startRouter →
# applyRouterSwitch(install: false) → switchPluginNow → ClaudePlugin.write, which creates plugin-sessions and relay,
# and ClaudePlugin.ensureKey, which makes relay.key). They go before the move so a re-run never touches the new app's
# own. The plugin folder is removed in step 5 after Claude Code has dropped any marketplace that points at the old path.
for source in "$LOOKOUT_DATA" "$COMPUTER_DATA"; do
  if [ -e "$source" ] || [ -L "$source" ]; then
    [ -d "$source" ] || die "\"$source\" exists but isn't a data folder."
    [ -z "$SOURCE_DATA" ] || die "both \"$SOURCE_DATA\" and \"$source\" exist. Choose one to keep; the script won't merge them."
    SOURCE_DATA="$source"
  fi
done
if [ -n "$SOURCE_DATA" ] && { [ -e "$NEW_DATA" ] || [ -L "$NEW_DATA" ]; }; then
  die "both \"$SOURCE_DATA\" and \"$NEW_DATA\" exist. Move or remove one by hand; the script won't merge or overwrite them."
elif [ -n "$SOURCE_DATA" ]; then
  for name in plugin-sessions relay relay.key; do
    if [ -e "$SOURCE_DATA/$name" ]; then say "Removing the old $name (Fjord makes its own)."; run rm -rf "$SOURCE_DATA/$name"; fi
  done
  say "Moving \"$SOURCE_DATA\" to \"$NEW_DATA\"."
  run mv "$SOURCE_DATA" "$NEW_DATA"
elif [ -e "$NEW_DATA" ] || [ -L "$NEW_DATA" ]; then
  [ -d "$NEW_DATA" ] || die "\"$NEW_DATA\" exists but isn't a data folder."
  say "Fjord's data folder is already there."
else
  say "No Lookout or Fjord data folder; nothing to move."
fi

step "2b. Saved state"
# Names the app saves that said Lookout: the Router's sessions it started (`lookoutStarted`, now `fjordStarted`) and the
# GitHub folder's mark (`lookout.github`, now `fjord.github`). The file as it was is kept beside it, once.
STATE="$NEW_DATA/state.json"
if $DRY && [ ! -d "$NEW_DATA" ] && [ -n "$SOURCE_DATA" ]; then STATE="$SOURCE_DATA/state.json"; fi
if [ ! -f "$STATE" ]; then
  say "No state.json; nothing to rename."
else
  # 0 found, 1 not found; anything else (unreadable) stops here rather than being taken as nothing to do.
  found=0; grep -q '"lookoutStarted"\|"lookout\.github"' "$STATE" || found=$?
  if [ "$found" -gt 1 ]; then die "couldn't read \"$STATE\"."
  elif [ "$found" -eq 1 ]; then say "state.json has nothing named after Lookout."
  elif $DRY; then say "Would rename lookoutStarted and lookout.github in \"$STATE\" (a copy kept as state.json.pre-fjord)."
  else
    say "Renaming lookoutStarted and lookout.github in state.json (the file as it was: state.json.pre-fjord)."
    # The copy is complete before it has its name: one left by a run that stopped halfway is never taken for it.
    if [ ! -e "$STATE.pre-fjord" ]; then
      if ! { cp -p "$STATE" "$STATE.pre-fjord.partial" && mv "$STATE.pre-fjord.partial" "$STATE.pre-fjord"; }; then
        rm -f "$STATE.pre-fjord.partial"
        die "couldn't copy state.json aside; nothing was changed."
      fi
    fi
    "$PY" -I -c '
import json, os, sys, tempfile
path = sys.argv[1]
def rename(v):
    if isinstance(v, dict):
        return {("fjordStarted" if k == "lookoutStarted" else k):
                ("fjord.github" if k == "symbol" and x == "lookout.github" else rename(x)) for k, x in v.items()}
    if isinstance(v, list):
        return [rename(x) for x in v]
    return v
with open(path) as f:
    state = json.load(f)
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".state.json.")
try:
    with os.fdopen(fd, "w") as f:
        json.dump(rename(state), f, ensure_ascii=False)
    os.chmod(tmp, os.stat(path).st_mode & 0o7777)
    os.replace(tmp, path)
except BaseException:
    os.unlink(tmp)
    raise' "$STATE" || die "couldn't rewrite state.json (the original is in state.json.pre-fjord)."
  fi
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
# The window's place, saved under its old autosave name: kept under the new one.
OLD_FRAME="NSWindow Frame LookoutApp"
if frame=$(defaults read "$NEW_ID" "$OLD_FRAME" 2>/dev/null) \
    && ! defaults read "$NEW_ID" "NSWindow Frame FjordApp" >/dev/null 2>&1; then
  say "Keeping the window's place under its new name."
  run defaults write "$NEW_ID" "NSWindow Frame FjordApp" "$frame"
  run defaults delete "$NEW_ID" "$OLD_FRAME"
fi

step "4. Keychain"
# The secret is read into a variable (command substitution, never on a command line) and handed to `security -i` on
# its stdin, so it doesn't show in `ps`. That needs it quoted for security's own parser, so only plain token characters
# are accepted; anything else falls back to `-w <secret>` on the command line, briefly visible to `ps` on this machine.
# The copy is read back and compared before the old item goes. macOS asks once to let `security` read the old item,
# and Fjord may still ask once when it first reads the new one.
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
# Remove Lookout's hook and the Fjord hook only when its script still points into an old app bundle. The new app will
# write the hook again when the Router is switched off and on. The settings edit follows FormHookInstaller.uninstall:
# it removes only our command from hooks.PermissionRequest and keeps any other hooks in the entry. It writes in the
# format the app and Claude Code use (2 spaces, " : "), through a symlink to its target.
SETTINGS="$CLAUDE_DIR/settings.json"
LOOKOUT_HOOK="$CLAUDE_DIR/hooks/lookout-form.sh"
FJORD_HOOK="$CLAUDE_DIR/hooks/fjord-form.sh"
FJORD_HOOK_STALE=false
if [ -f "$FJORD_HOOK" ] && {
  grep -Fq '/Applications/Lookout.app/' "$FJORD_HOOK" \
    || grep -Fq '/Applications/Fjord Computer.app/' "$FJORD_HOOK"
}; then
  FJORD_HOOK_STALE=true
fi
if [ -e "$SETTINGS" ]; then
  [ -x "$PY" ] || die "$PY isn't there (install the Xcode Command Line Tools: xcode-select --install)."
  dry=0; $DRY && dry=1
  remove_fjord=0; $FJORD_HOOK_STALE && remove_fjord=1
  "$PY" -I - "$SETTINGS" "$LOOKOUT_HOOK" "$FJORD_HOOK" "$remove_fjord" "$dry" <<'PY'
import json, os, sys, tempfile
path, lookout_hook, fjord_hook = os.path.realpath(sys.argv[1]), sys.argv[2], sys.argv[3]
remove_fjord, dry = sys.argv[4] == "1", sys.argv[5] == "1"
scripts = {lookout_hook}
if remove_fjord:
    scripts.add(fjord_hook)
commands = scripts | {"'" + script.replace("'", "'\\''") + "'" for script in scripts}
raw = open(path, "rb").read()
try:
    root = json.loads(raw)
except ValueError:
    sys.exit("Stopped: %s isn't valid JSON; fix it and run this again." % sys.argv[1])
if not isinstance(root, dict):
    sys.exit("Stopped: %s doesn't hold a JSON object." % sys.argv[1])
def is_us(h):
    return isinstance(h, dict) and h.get("command") in commands
hooks = root.get("hooks")
entries = hooks.get("PermissionRequest") if isinstance(hooks, dict) else None
if not isinstance(entries, list) or not any(
        isinstance(e, dict) and isinstance(e.get("hooks"), list) and any(map(is_us, e["hooks"])) for e in entries):
    print("No old Fjord or Lookout form hook in %s." % sys.argv[1])
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
    print("Would remove the old form hook from %s." % sys.argv[1])
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
print("Removed the old form hook from %s." % sys.argv[1])
PY
else
  say "No $SETTINGS."
fi
for f in "$LOOKOUT_HOOK" "$SETTINGS.lookout-backup"; do
  if [ -e "$f" ]; then say "Removing $f."; run rm -f "$f"; fi
done
if $FJORD_HOOK_STALE && [ -e "$FJORD_HOOK" ]; then
  say "Removing the Fjord hook script that points into an old app bundle."
  run rm -f "$FJORD_HOOK"
fi

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
marketplace_path() {
  "$PY" -I -c '
import json, sys
try:
    items = json.load(sys.stdin)
    if not isinstance(items, list) or not all(isinstance(i, dict) for i in items):
        sys.exit(2)
    for item in items:
        if item.get("name") == sys.argv[1]:
            path = item.get("path")
            print(path if isinstance(path, str) else "")
            sys.exit(0)
    print("")
except Exception:
    sys.exit(2)' "$1"
}
PLUGIN_DATA="$NEW_DATA"
if $DRY && [ ! -d "$NEW_DATA" ] && [ -n "$SOURCE_DATA" ]; then PLUGIN_DATA="$SOURCE_DATA"; fi
FJORD_PLUGIN="$PLUGIN_DATA/claude-plugin"
legacy_fjord_path=false
if [ -n "$SOURCE_DATA" ]; then legacy_fjord_path=true; fi
if [ -f "$FJORD_PLUGIN/config.json" ] && {
  grep -Fq "$LOOKOUT_DATA/" "$FJORD_PLUGIN/config.json" \
    || grep -Fq "$COMPUTER_DATA/" "$FJORD_PLUGIN/config.json"
}; then
  legacy_fjord_path=true
fi
plugin_gone=false
if CLAUDE=$(find_claude); then
  say "Claude Code: $CLAUDE"
  plugins=$(claude plugin list --json) || die "\`claude plugin list --json\` failed."
  marketplaces=$(claude plugin marketplace list --json) || die "\`claude plugin marketplace list --json\` failed."
  fjord_marketplace_path=$(printf '%s' "$marketplaces" | marketplace_path fjord) \
    || die "couldn't read \`claude plugin marketplace list --json\`'s answer."
  if [ -n "$fjord_marketplace_path" ] && [ "$fjord_marketplace_path" != "$NEW_DATA/claude-plugin" ]; then
    legacy_fjord_path=true
  fi

  if printf '%s' "$plugins" | lists id lookout@lookout; then
    say "Uninstalling the old lookout@lookout plugin."
    run claude plugin uninstall lookout@lookout --scope user
  else
    [ $? -eq 1 ] || die "couldn't read \`claude plugin list --json\`'s answer."
    say "The old lookout@lookout plugin isn't installed."
  fi
  if $legacy_fjord_path; then
    if printf '%s' "$plugins" | lists id fjord@fjord; then
      say "Uninstalling the plugin that points at an old Fjord data folder."
      run claude plugin uninstall fjord@fjord --scope user
    else
      [ $? -eq 1 ] || die "couldn't read \`claude plugin list --json\`'s answer."
      say "No plugin from an old Fjord data folder is installed."
    fi
  fi

  if printf '%s' "$marketplaces" | lists name lookout; then
    say "Removing the old lookout marketplace."
    run claude plugin marketplace remove lookout
  else
    [ $? -eq 1 ] || die "couldn't read \`claude plugin marketplace list --json\`'s answer."
    say "The old lookout marketplace isn't there."
  fi
  if $legacy_fjord_path; then
    if printf '%s' "$marketplaces" | lists name fjord; then
      say "Removing the marketplace that points at an old Fjord data folder."
      run claude plugin marketplace remove fjord
    else
      [ $? -eq 1 ] || die "couldn't read \`claude plugin marketplace list --json\`'s answer."
      say "No marketplace points at an old Fjord data folder."
    fi
  fi
  plugin_gone=true
else
  say "Claude Code (the copy the Claude app bundles) wasn't found: any old Fjord or Lookout plugin and marketplace"
  say "have to go by hand (/plugin in Claude Code)."
fi
# A moved plugin folder can still name the old absolute paths in config.json. Remove only the known old plugin manifests;
# a current Fjord plugin at the new data path is left alone on re-runs.
OLD_PLUGIN="$FJORD_PLUGIN"
legacy_flag=0
if $legacy_fjord_path; then legacy_flag=1; fi
if $plugin_gone && [ -f "$OLD_PLUGIN/.claude-plugin/plugin.json" ] \
    && "$PY" -I - "$OLD_PLUGIN/.claude-plugin/plugin.json" "$legacy_flag" <<'PY'
import json, sys
name = json.load(open(sys.argv[1])).get("name")
sys.exit(0 if name == "lookout" or (name == "fjord" and sys.argv[2] == "1") else 1)
PY
then
  say "Removing the old plugin folder (Fjord writes a fresh one)."
  run rm -rf "$OLD_PLUGIN"
fi

step "6. Caches"
CACHE="$HOME/Library/Caches/$OLD_ID"
if [ -e "$CACHE" ]; then say "Removing $CACHE."; run rm -rf "$CACHE"; else say "No old cache."; fi

step "7. Old app bundles"
if [ -d "$NEW_APP" ]; then
  for old_app in "$OLD_LOOKOUT_APP" "$OLD_COMPUTER_APP"; do
    if [ -e "$old_app" ] || [ -L "$old_app" ]; then
      say "Removing the old app bundle \"$old_app\"."
      run rm -rf "$old_app"
    else
      say "No old app bundle at \"$old_app\"."
    fi
  done
else
  say "Leaving old app bundles in place: install \"$NEW_APP\" before removing them."
fi

step "Left to you"
say "- Remove any previous app entries from System Settings › General › Login Items."
say "  Open Fjord and enable Launch at Login again if you want it."
say "- Open Fjord. With the Router on, it installs the fjord@fjord plugin at launch, but not a missing form hook"
say "  (at launch it only re-installs a hook that is outdated, not one that is missing): switch the Router off and"
say "  on once in Settings to install it."
say "- Claude Code sessions already open keep the old plugin until they restart (or /reload-plugins)."
$DRY && say "(Dry run: nothing was changed.)"
say "Done."
