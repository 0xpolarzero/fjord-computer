import CryptoKit
import Foundation
import Security

/// Lookout's Claude Code plugin: what the person sends from the Router reaches a session as their own words. The Router's
/// message travels on Claude Code's peer channel, signed with a key only Lookout holds (`RelaySigner`); the plugin, running
/// in each session, checks the signature and submits the body as the person's prompt. It also leaves a file per session it
/// runs in, so Lookout knows where a message can be delivered that way.
///
/// The sources are kept in the repository under `Resources/ClaudePlugin` (where `claude plugin test` runs their tests) and
/// embedded here, so the app writes them without bundling resources; a test keeps the two the same.
enum ClaudePlugin {
    static let name = "lookout"
    /// `<plugin>@<marketplace>`: the folder is its own marketplace, of the same name.
    static let id = "lookout@lookout"
    static let description = "Delivers what you send from Lookout's Router to this session as your own words."

    /// The version Claude Code records: the app's, and the sources' own digest, so a change in either is a new version.
    static func version(app: String) -> String {
        let digest = SHA256.hash(data: Data((register + hooksJSON + marketplaceJSON).utf8))
        let short = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return app + (app.contains("-") ? "." : "-") + "r" + short
    }

    static func pluginJSON(version: String) -> String {
        let manifest: [String: Any] = ["name": name, "version": version, "description": description, "author": ["name": "Lookout"]]
        let data = (try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    /// Writes the plugin's folder: its sources, its manifest at `version`, and the absolute paths the plugin reads (a hooks
    /// module can't read the environment): the key, where it leaves its presence files, and Claude Code's registry of
    /// processes. The key itself lives outside the folder (`ensureKey`): `claude plugin install` copies the folder into
    /// Claude Code's cache, and keeps the copy after an uninstall.
    static func write(to folder: URL, version: String, presence: URL, key: URL, registry: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.createDirectory(at: presence, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let inbox = RelayInbox.root(besidePresence: presence)
        try fm.createDirectory(at: inbox, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let config = try JSONSerialization.data(withJSONObject: ["keyPath": key.path, "presenceDir": presence.path,
                                                                 "sessionsDir": registry.path, "inboxDir": inbox.path],
                                                options: [.sortedKeys, .withoutEscapingSlashes])
        let files: [(String, Data)] = [
            (".claude-plugin/plugin.json", Data(pluginJSON(version: version).utf8)),
            (".claude-plugin/marketplace.json", Data(marketplaceJSON.utf8)),
            ("hooks/hooks.json", Data(hooksJSON.utf8)),
            ("hooks/register.ts", Data(register.utf8)),
            ("config.json", config + Data("\n".utf8)),
        ]
        for (path, data) in files {
            let url = folder.appendingPathComponent(path)
            // Unchanged files are left alone: Claude Code watches the folder.
            if (try? Data(contentsOf: url)) == data { continue }
            try PrivateFile.write(data, to: url, mode: 0o644)
        }
    }

    /// The key, made once: 32 random bytes, hex, readable by the person alone. Returns it.
    @discardableResult
    static func ensureKey(at url: URL) throws -> String {
        if let key = key(at: url) { return key }
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        let key = bytes.map { String(format: "%02x", $0) }.joined()
        try PrivateFile.write(Data((key + "\n").utf8), to: url, mode: 0o600)
        return key
    }

    /// The key Lookout signs with, if it has been made.
    static func key(at url: URL) -> String? {
        let text = (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// What a presence file names the key by: the first 16 hex digits of its SHA-256 (the key itself is never written there).
    static func keyID(of key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    /// Turning the Router off retires the key: a message signed before can't be delivered after.
    static func removeKey(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// What the plugin writes for the session it runs in: `live` with the process it found in Claude Code's registry.
    struct Presence: Decodable {
        var state: String
        var sessionId: String?
        var pid: Int32?
        var startedAt: Int64?
        var keyId: String?
        /// When the plugin last renewed it (ms since 1970).
        var renewedAt: Int64?
        /// What this copy of the plugin can do (`inbox-v1`: it takes signed messages from its inbox folder). Absent in an
        /// older plugin, which Lookout reaches over the peer channel instead.
        var capabilities: [String]?
    }

    /// The plugin takes signed messages from `relay/<session id>/` (see `RelayInbox`).
    static let inboxCapability = "inbox-v1"
    /// The plugin reads v2 messages (a model and an effort inside the signed bytes) from its inbox and applies them.
    static let settingsCapability = "settings-v1"

    /// How long a presence lasts without being renewed: the plugin renews it every 10 s.
    static let lease: TimeInterval = 30

    /// The time a lease is judged at: the clock, or in a test run a fixed moment, so a test's presence files (written at
    /// it) never run out however long the run takes. A test of the lease itself passes its own `now`.
    static var leaseNow: Date { UnderTest.isRunning ? Date(timeIntervalSince1970: 2_000_000_000) : Date() }

    /// The Claude Code sessions (their CLI session ids) the plugin runs in now. A file counts only while its process is
    /// alive and still registered for that session, started when the file says, and only if it was written under the key
    /// Lookout holds now (`keyID`): a crash, a resume in a process without the plugin, a /clear (a new session id), or a
    /// plugin unloaded while the Router was off leaves a file that no longer counts. And it is a lease, renewed by the
    /// plugin: one not renewed within `lease` of `now` is a plugin gone without a word (disabled and reloaded away).
    static func sessions(in presence: URL, registry: [Int32: [ClaudePeers.Registered]], keyID: String?, now: Date = leaseNow,
                         alive: (Int32) -> Bool = FormBridge.processAlive) -> Set<String> {
        Set(live(in: presence, registry: registry, keyID: keyID, now: now, alive: alive).keys)
    }

    /// `sessions(in:registry:keyID:now:alive:)` with each session's presence, so what the plugin there can do is known too.
    static func live(in presence: URL, registry: [Int32: [ClaudePeers.Registered]], keyID: String?, now: Date = leaseNow,
                     alive: (Int32) -> Bool = FormBridge.processAlive) -> [String: Presence] {
        guard let keyID else { return [:] }
        let nowMs = now.timeIntervalSince1970 * 1000, leaseMs = lease * 1000
        let files = (try? FileManager.default.contentsOfDirectory(at: presence, includingPropertiesForKeys: nil)) ?? []
        return Dictionary(files.compactMap { url -> (String, Presence)? in
            guard !url.lastPathComponent.hasPrefix("."), let data = try? Data(contentsOf: url),
                  let file = try? JSONDecoder().decode(Presence.self, from: data), file.state == "live", file.keyId == keyID,
                  // In Double: a file's value at either end of Int64 must not trap the subtraction.
                  let renewed = file.renewedAt, abs(nowMs - Double(renewed)) < leaseMs,
                  let id = file.sessionId, id == url.lastPathComponent, let pid = file.pid, alive(pid),
                  registry[pid]?.contains(where: { $0.sessionID == id && $0.startedAt == file.startedAt }) == true
            else { return nil }
            return (id, file)
        }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Sources (the same as Resources/ClaudePlugin; see ClaudePluginTests)

    static let register = #"""
import type { EngineInterface, Register } from 'claude-code'

// Lookout's Router relays what the person writes to this session. The message arrives on the peer channel, signed by
// the Lookout app with a key only it holds (a file of Lookout's own, readable by the person alone, never in this
// folder: Claude Code copies an installed plugin's folder into its cache). A valid one, addressed to this session, fresh
// and never seen before, is taken off the peer channel and submitted as the person's own words. Anything else passes
// on untouched, as the peer message it is.
//
// The wire format: a header line, then the body's UTF-8 bytes in base64 on one line (so the peer channel's escaping and
// any Unicode normalization can't touch them):
//   ⟦lookout v1 <target session id> <nonce> <ms since 1970> <hex HMAC-SHA256>⟧\n<base64 body>
// The MAC covers the UTF-8 bytes of "v1\n<target>\n<nonce>\n<ms>\n" followed by the body's own UTF-8 bytes.
//
// Two ways in, one check. The peer channel (`session.receive`) is the original way and stays as the fallback for a Lookout
// that can't reach this plugin directly. The inbox is the direct way, with no model in between: Lookout writes the very
// same signed text to `<inboxDir>/<session id>/<nonce>.msg` (atomically: a dot-file renamed into place), the plugin polls
// that folder every half second, runs the same check, and answers with `<nonce>.ack` beside it ("ok", or "refused: why").
// Lookout reads the ack and deletes both files; the plugin has no way to delete, and needs none.
// Presence files list `capabilities`, so a Lookout knows which way a session can be reached.
//
// `settings-v1`: a v2 message carries the model and effort the session should use, inside the signed bytes:
//   ⟦lookout v2 <target> <nonce> <ms> <model|-> <effort|-> <hex HMAC-SHA256>⟧\n<base64 body>
// with the MAC over "v2\n<target>\n<nonce>\n<ms>\n<model|->\n<effort|->\n" and the body. A plugin without the capability
// sees an unknown header (unsigned) and ignores it; Lookout only sends v2 to a plugin that advertises `settings-v1`.
// From the inbox (never the peer channel, whose hook the turn waits on), the plugin sets the model, then the effort (a
// model switch resets the effort), with `/model` and `/effort` run for this session only, and only then submits the
// text, so the turn it starts uses them. The ack says what happened: "ok model=opus effort=high", or "model=error:why".
//
// Lookout writes this file; edits are overwritten.

const HEADER = /(?:^|\n)⟦lookout (?:v1 (\S+) (\S+) (\d+)|v2 (\S+) (\S+) (\d+) (\S+) (\S+)) ([0-9a-f]{64})⟧\n/
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/
const CLOSE = '</cross-session-message>'
const WINDOW_MS = 10 * 60 * 1000
const NONCE = 'nonce.'
export const CAPABILITIES = ['inbox-v1', 'settings-v1']
const POLL_MS = 500
const ACTIVATION = crypto.randomUUID()

const enc = new TextEncoder()
const hex = (bytes: Uint8Array) => [...bytes].map((x) => x.toString(16).padStart(2, '0')).join('')
const join = (...parts: Uint8Array[]) => {
  const all = new Uint8Array(parts.reduce((n, p) => n + p.length, 0))
  let at = 0
  for (const p of parts) {
    all.set(p, at)
    at += p.length
  }
  return all
}
const sha256 = async (...parts: Uint8Array[]) => new Uint8Array(await crypto.subtle.digest('SHA-256', join(...parts)))

/** HMAC-SHA256 (RFC 2104) on the environment's SHA-256, the one digest it has. */
export const hmac = async (key: Uint8Array, message: Uint8Array) => {
  const block = new Uint8Array(64)
  block.set(key.length > 64 ? await sha256(key) : key)
  const inner = block.map((x) => x ^ 0x36)
  const outer = block.map((x) => x ^ 0x5c)
  return hex(await sha256(outer, await sha256(inner, message)))
}

/** The model and effort a v2 message asks for; `-` on the wire is none. */
export type Settings = { model?: string; effort?: string }

/** What the MAC covers: the version, the target, the nonce and the time, one per line (v2: also the model and the effort),
 * then the body's bytes. */
export const macInput = (target: string, nonce: string, ts: string, body: Uint8Array, settings?: Settings) =>
  join(
    enc.encode(
      settings
        ? `v2\n${target}\n${nonce}\n${ts}\n${settings.model ?? '-'}\n${settings.effort ?? '-'}\n`
        : `v1\n${target}\n${nonce}\n${ts}\n`,
    ),
    body,
  )

const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']
/** A model `/model` takes: an alias (with the 1M-context suffix), or a full id. */
const MODEL = /^(?:(?:opus|sonnet|haiku|fable)|claude-[a-z0-9][a-z0-9.-]*)(?:\[1m\])?$/
/** Why a settings request can't be applied (undefined: fine). */
export const invalid = (s: Settings) =>
  s.model !== undefined && !MODEL.test(s.model) ? `invalid model ${JSON.stringify(s.model.slice(0, 40))}`
    : s.effort !== undefined && !EFFORTS.includes(s.effort) ? `invalid effort ${JSON.stringify(s.effort.slice(0, 40))}`
      : undefined

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

/** Standard base64 (padded) to bytes; undefined for anything else. */
export const fromBase64 = (text: string) => {
  if (!BASE64.test(text) || text.length % 4 !== 0) return undefined
  const clean = text.replace(/=+$/, '')
  const out = new Uint8Array(Math.floor((clean.length * 3) / 4))
  let bits = 0
  let value = 0
  let at = 0
  for (const c of clean) {
    value = (value << 6) | ALPHABET.indexOf(c)
    bits += 6
    if (bits >= 8) {
      bits -= 8
      out[at++] = (value >> bits) & 0xff
    }
  }
  return out
}

/** The signed message in a delivery: its header's fields and the body's bytes (the peer envelope's close left out). */
export const parse = (text: string) => {
  const m = HEADER.exec(text)
  if (!m) return undefined
  const header = m[0]
  const v2 = m[4] !== undefined
  const [target, nonce, ts] = v2 ? [m[4], m[5], m[6]] : [m[1], m[2], m[3]]
  const mac = m[9]
  const settings: Settings | undefined = v2
    ? { model: m[7] === '-' ? undefined : m[7], effort: m[8] === '-' ? undefined : m[8] }
    : undefined
  let rest = text.slice(m.index + header.length)
  const close = rest.indexOf(CLOSE)
  if (close >= 0) rest = rest.slice(0, close)
  const body = fromBase64(rest.trim())
  if (!body) return undefined
  return { target, nonce, ts, mac, body, settings }
}

/** Compares two MACs in time that doesn't depend on where they differ. */
const same = (a: string, b: string) => {
  if (a.length !== b.length) return false
  let d = 0
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i)
  return d === 0
}

/** One nonce check-and-claim at a time in this copy of the plugin: two deliveries of the same message can't both pass. */
let claims: Promise<unknown> = Promise.resolve()
const exclusive = <T>(work: () => Promise<T>): Promise<T> => {
  const run = claims.then(work, work)
  claims = run.catch(() => undefined)
  return run
}

/** Where Lookout keeps the key and the presence files, and Claude Code its registry of processes, as absolute paths (a
 * hooks module can't read the environment). */
type Config = { keyPath?: string; presenceDir?: string; sessionsDir?: string; inboxDir?: string }

async function config($: EngineInterface) {
  return JSON.parse(await $.fs.read(`${$.plugin.root}/config.json`)) as Config
}

/** Which key a presence file was written under: the first 16 hex digits of the key's SHA-256, never the key. */
export const keyId = async (key: string) => hex(await sha256(enc.encode(key))).slice(0, 16)

/** The session this copy last said it runs in, under which key, where it said so, and the process it found for it. */
let marked: { sessionId: string; presenceDir: string; keyId: string; pid: number; startedAt: number } | undefined

/** Says which session this plugin runs in, bound to its process (Claude Code's registry entry for the session: its pid
 * and start time) and to the key Lookout holds now, so Lookout can tell a live session from one that crashed, was resumed
 * without the plugin, or unloaded it while the Router was off. It is a lease: renewed at every turn and every 10 s
 * (`renewedAt`), so a plugin disabled and reloaded away, which says nothing as it goes, stops counting within 30 s.
 * The registry is read again when the session id changes (a /clear starts a new one with no session.start) or the key
 * does (the Router was switched off and on: its old presence files are gone). */
async function mark($: EngineInterface) {
  const { presenceDir, sessionsDir, keyPath } = await config($)
  if (!presenceDir || !sessionsDir || !keyPath) return
  const key = (await $.fs.read(keyPath).catch(() => '')).trim()
  if (!key) {
    // The Router is off: nothing to say until there's a key again.
    marked = undefined
    return
  }
  const id = await keyId(key)
  const sessionId = await $.session.id()
  let own: { pid: number; startedAt: number } | undefined =
    marked?.sessionId === sessionId && marked.keyId === id ? { pid: marked.pid, startedAt: marked.startedAt } : undefined
  if (!own) for (const entry of await $.fs.list(sessionsDir)) {
    if (!entry.name.endsWith('.json')) continue
    let found: { sessionId?: unknown; pid?: unknown; startedAt?: unknown }
    try {
      found = JSON.parse(await $.fs.read(`${sessionsDir}/${entry.name}`))
    } catch {
      continue
    }
    if (found?.sessionId === sessionId && typeof found.pid === 'number') {
      const startedAt = typeof found.startedAt === 'number' ? found.startedAt : 0
      if (!own || startedAt > own.startedAt) own = { pid: found.pid, startedAt }
    }
  }
  if (!own) return
  if (marked && marked.sessionId !== sessionId) {
    await $.fs.write(`${marked.presenceDir}/${marked.sessionId}`, `${JSON.stringify({ state: 'ended' })}\n`)
  }
  const renewedAt = await $.clock.now()
  const presence = { state: 'live', sessionId, pid: own.pid, startedAt: own.startedAt, keyId: id, renewedAt, activation: ACTIVATION, capabilities: CAPABILITIES }
  await $.fs.write(`${presenceDir}/${sessionId}`, `${JSON.stringify(presence)}\n`)
  marked = { sessionId, presenceDir, keyId: id, pid: own.pid, startedAt: own.startedAt }
}

async function unmark($: EngineInterface) {
  if (!marked) return
  await $.fs.write(`${marked.presenceDir}/${marked.sessionId}`, `${JSON.stringify({ state: 'ended' })}\n`)
  marked = undefined
}

/** Checks a signed text the way both ways in must, and submits it as the person's own words. `unsigned` means it isn't
 * Lookout's at all (the peer channel then passes it on); anything else is a refusal with its reason. */
export async function accept(
  $: EngineInterface,
  text: string,
  apply = false,
): Promise<{ ok: true; applied?: string } | { ok: false; reason: string }> {
  const signed = parse(text)
  if (!signed) return { ok: false, reason: 'unsigned' }
  const { keyPath } = await config($)
  if (!keyPath) return { ok: false, reason: 'no key configured' }
  const key = (await $.fs.read(keyPath)).trim()
  const expected = await hmac(enc.encode(key), macInput(signed.target, signed.nonce, signed.ts, signed.body, signed.settings))
  const now = await $.clock.now()
  const ts = Number(signed.ts)
  if (!same(expected, signed.mac)) return { ok: false, reason: 'bad signature' }
  if (signed.target !== (await $.session.id())) return { ok: false, reason: 'addressed to another session' }
  if (!(Math.abs(now - ts) < WINDOW_MS)) return { ok: false, reason: 'stale' }
  const bad = signed.settings && invalid(signed.settings)
  if (bad) return { ok: false, reason: bad }
  // A leading byte-order mark is part of what was written: the decoder drops one, so exactly one is put back.
  let decoded: string
  try {
    decoded = new TextDecoder('utf-8', { fatal: true }).decode(signed.body)
  } catch {
    return { ok: false, reason: 'not UTF-8' }
  }
  const bom = signed.body[0] === 0xef && signed.body[1] === 0xbb && signed.body[2] === 0xbf
  const body = bom ? `\uFEFF${decoded}` : decoded
  // Each nonce is a key of its own in the store (it outlives reloads and restarts), kept while its message's time is
  // inside the window: past it the message is refused as stale anyway.
  const claimed = await exclusive(async () => {
    if ((await $.store.get(NONCE + signed.nonce)) !== undefined) return false
    await $.store.set(NONCE + signed.nonce, ts)
    for (const name of await $.store.keys()) {
      if (!name.startsWith(NONCE)) continue
      const at = Number(await $.store.get(name))
      if (!(Math.abs(now - at) < WINDOW_MS)) await $.store.delete(name)
    }
    return true
  })
  if (!claimed) return { ok: false, reason: 'already delivered' }
  // The settings first, so the turn the text starts uses them: the model, then the effort (a model resets it). Each can fail
  // on its own; the person's words go either way. Only from the inbox (`apply`): never from inside a hook a turn waits on.
  const applied: string[] = []
  if (apply && signed.settings) {
    for (const [command, args] of [['model', signed.settings.model], ['effort', signed.settings.effort]] as const) {
      if (args === undefined) continue
      try {
        await $.command.run({ command, args })
        applied.push(`${command}=${args}`)
      } catch (error) {
        const why = String((error as { message?: unknown })?.message ?? error).replace(/\s+/g, '_').slice(0, 80)
        applied.push(`${command}=error:${why}`)
      }
    }
  }
  void $.prompt.submit({ text: body, asUser: true })
  return applied.length ? { ok: true, applied: applied.join(' ') } : { ok: true }
}

/** When the look in progress began (0: none). A look that hangs is given up on after `POLL_STUCK_MS`, so one stuck call can't
 * silence the inbox for good; two looks at once never happen otherwise (each message gets exactly one ack). */
let pollingSince = 0
const POLL_STUCK_MS = 5000

/** One look at this session's inbox: every message without an ack is checked, submitted or refused, and answered. */
export async function poll($: EngineInterface) {
  const began = await $.clock.now()
  if (pollingSince && Math.abs(began - pollingSince) < POLL_STUCK_MS) return
  pollingSince = began
  try {
    const { inboxDir } = await config($)
    if (!inboxDir) return
    const dir = `${inboxDir}/${await $.session.id()}`
    const names = new Set((await $.fs.list(dir)).map((entry) => entry.name))
    for (const name of [...names].sort()) {
      if (!name.endsWith('.msg') || names.has(`${name.slice(0, -4)}.ack`)) continue
      const text = await $.fs.read(`${dir}/${name}`).catch(() => undefined)
      if (text === undefined) continue
      const outcome = await accept($, text, true).catch((error) => ({ ok: false as const, reason: String(error?.message ?? error) }))
      await $.fs.write(`${dir}/${name.slice(0, -4)}.ack`, outcome.ok ? `ok${outcome.applied ? ` ${outcome.applied}` : ''}\n` : `refused: ${outcome.reason}\n`)
    }
  } catch {
    // No folder yet (nothing was ever sent here), or it can't be read: nothing to do until the next look.
  } finally {
    if (pollingSince === began) pollingSince = 0
  }
}

let timer: { cancel: () => void } | undefined

export const register: Register = (on) => {
  on('session.receive', async ($, e, next) => {
    const outcome = await accept($, e.text)
    if (!outcome.ok) return next(e)
    return { consumed: 'relayed by Lookout as the person’s own message' }
  }).catch(($, e, next) => next(e))

  on('session.start', async ($, e, next) => {
    await mark($).catch(() => undefined)
    // The registry may not list the process yet, and a /clear changes the session's id: looked at again now and then.
    $.clock.every(10_000, () => void mark($).catch(() => undefined))
    timer?.cancel()
    timer = $.clock.every(POLL_MS, () => void poll($))
    return next(e)
  })
  on('turn.start', async ($, e, next) => {
    await mark($).catch(() => undefined)
    return next(e)
  })
  on('session.end', async ($, e, next) => {
    await unmark($).catch(() => undefined)
    return next(e)
  })
}

"""#

    static let hooksJSON = #"""
{ "modules": ["./register.ts"] }

"""#

    static let marketplaceJSON = #"""
{
  "name": "lookout",
  "owner": { "name": "Lookout" },
  "description": "Lookout's own plugin, kept by the Lookout app.",
  "plugins": [{ "name": "lookout", "source": "./", "description": "Delivers what you send from Lookout's Router to this session as your own words." }]
}

"""#
}

// MARK: - Signing

/// Signs a message for one session the way Lookout's plugin checks it: a header line
/// `⟦lookout v1 <target> <nonce> <ms> <hex HMAC-SHA256>⟧`, then the body. The MAC covers `v1`, the target, the nonce, the
/// time and the body, one per line; its key is `relay.key`'s text.
enum RelaySigner {
    /// The text to send to the session whose CLI session id is `target`: the header line, then the body's UTF-8 bytes in
    /// standard base64 (padded, one line), so the peer channel's escaping and Unicode normalization can't change them.
    ///
    /// With a `model` or an `effort` (already allowlisted, see `SessionSettings`) the header is v2 and the MAC covers them, so
    /// they can't be forged or changed on the way; only a plugin that says `settings-v1` knows that header, so it's the
    /// caller's to ask `Store.supportsSettings` first. Without either it is the v1 text, which every plugin reads.
    static func sign(body: String, target: String, key: String, nonce: UUID = UUID(), now: Date = Date(),
                     model: String? = nil, effort: String? = nil) -> String {
        let ts = String(RouterFeed.Stamp.ms(now))
        let id = nonce.uuidString.lowercased()
        let bytes = Data(body.utf8)
        guard model != nil || effort != nil else {
            return "⟦lookout v1 \(target) \(id) \(ts) \(mac(key: key, target: target, nonce: id, ts: ts, body: bytes))⟧\n"
                + bytes.base64EncodedString()
        }
        let m = model ?? "-", e = effort ?? "-"
        return "⟦lookout v2 \(target) \(id) \(ts) \(m) \(e) \(mac(key: key, target: target, nonce: id, ts: ts, body: bytes, model: m, effort: e))⟧\n"
            + bytes.base64EncodedString()
    }

    /// The v2 MAC: `v2\n<target>\n<nonce>\n<ts>\n<model|->\n<effort|->\n` and the body.
    static func mac(key: String, target: String, nonce: String, ts: String, body: Data, model: String, effort: String) -> String {
        let input = Data("v2\n\(target)\n\(nonce)\n\(ts)\n\(model)\n\(effort)\n".utf8) + body
        let code = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: Data(key.utf8)))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    /// HMAC-SHA256, keyed with the key's hex text (UTF-8), over the UTF-8 of `v1\n<target>\n<nonce>\n<ts>\n` followed by
    /// the body's bytes.
    static func mac(key: String, target: String, nonce: String, ts: String, body: Data) -> String {
        let input = Data("v1\n\(target)\n\(nonce)\n\(ts)\n".utf8) + body
        let code = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: Data(key.utf8)))
        return code.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Installing

/// Installs the plugin with Claude Code's own commands (the bundled CLI, in a clean environment): the folder is added as a
/// marketplace and the plugin installed from it at the user scope. A folder marketplace is read in place, so a new version
/// of the sources reaches sessions on their next start (or `/reload-plugins`).
struct ClaudePluginInstaller {
    enum Status: Equatable, Sendable {
        case installed
        case notInstalled
        /// Installed from another folder, disabled, or Claude Code's installed copy (its cache) is not the version shipped.
        case outdated
        /// Claude Code (the copy the Claude app bundles) wasn't found.
        case noClaudeCode
    }

    struct Output: Sendable {
        var status: Int32
        var out: String
        var err: String
    }

    struct Failure: LocalizedError, Equatable {
        var message: String
        var errorDescription: String? { message }
    }

    /// Runs the CLI with arguments; tests answer for it.
    typealias Runner = @Sendable (_ binary: String, _ arguments: [String]) async throws -> Output

    var folder: URL
    var binary: String?
    var run: Runner

    func status(version: String) async throws -> Status {
        guard let binary else { return .noClaudeCode }
        guard let entry = try await plugins(binary).first(where: { $0["id"] as? String == ClaudePlugin.id }) else {
            return .notInstalled
        }
        let from = (entry["readFromFolder"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        // `version` is what Claude Code has installed (its cache, what sessions load); `folderVersion` is only what the
        // marketplace folder holds now, which is always the newest and says nothing about the cache.
        let current = entry["version"] as? String
        let enabled = entry["enabled"] as? Bool ?? true
        let sameFolder = from.map { $0 == folder.resolvingSymlinksInPath().path } ?? true  // older CLIs don't say
        return sameFolder && current == version && enabled ? .installed : .outdated
    }

    /// The version Claude Code has installed (its cache), if the plugin is installed.
    func installedVersion() async throws -> String? {
        guard let binary else { return nil }
        return try await plugins(binary).first(where: { $0["id"] as? String == ClaudePlugin.id })?["version"] as? String
    }

    /// Brings Claude Code to this folder at `version`, doing only the steps still needed.
    func install(version: String) async throws {
        guard let binary else { throw Failure(message: "Claude Code wasn't found (the Claude app bundles it).") }
        let path = folder.resolvingSymlinksInPath().path
        let marketplace = try await marketplaces(binary).first { $0["name"] as? String == ClaudePlugin.name }
        let markedPath = (marketplace?["path"] as? String).map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        if marketplace != nil, markedPath != path {
            // Another folder (the app moved): its plugin goes with it.
            if try await plugins(binary).contains(where: { $0["id"] as? String == ClaudePlugin.id }) {
                try await call(binary, ["plugin", "uninstall", ClaudePlugin.id, "--scope", "user"])
            }
            try await call(binary, ["plugin", "marketplace", "remove", ClaudePlugin.name])
        }
        if marketplace == nil || markedPath != path {
            try await call(binary, ["plugin", "marketplace", "add", folder.path, "--scope", "user"])
        }
        guard let entry = try await plugins(binary).first(where: { $0["id"] as? String == ClaudePlugin.id }) else {
            try await call(binary, ["plugin", "install", ClaudePlugin.id, "--scope", "user"])
            return
        }
        if entry["version"] as? String != version {
            // `plugin update` re-reads a directory marketplace's folder and refreshes the cache (no `marketplace update` needed).
            try await call(binary, ["plugin", "update", ClaudePlugin.id, "--scope", "user"])
            let now = try await installedVersion()
            guard now == version else {
                throw Failure(message: "Claude Code still has Lookout's plugin at \(now ?? "no version") after updating it to \(version).")
            }
        }
        if entry["enabled"] as? Bool == false {
            try await call(binary, ["plugin", "enable", ClaudePlugin.id, "--scope", "user"])
        }
    }

    /// Takes the plugin and its marketplace out of Claude Code; what isn't there is skipped.
    func uninstall() async throws {
        guard let binary else { return }
        if try await plugins(binary).contains(where: { $0["id"] as? String == ClaudePlugin.id }) {
            try await call(binary, ["plugin", "uninstall", ClaudePlugin.id, "--scope", "user"])
        }
        if try await marketplaces(binary).contains(where: { $0["name"] as? String == ClaudePlugin.name }) {
            try await call(binary, ["plugin", "marketplace", "remove", ClaudePlugin.name])
        }
    }

    private func plugins(_ binary: String) async throws -> [[String: Any]] {
        try await list(binary, ["plugin", "list", "--json"])
    }

    private func marketplaces(_ binary: String) async throws -> [[String: Any]] {
        try await list(binary, ["plugin", "marketplace", "list", "--json"])
    }

    private func list(_ binary: String, _ arguments: [String]) async throws -> [[String: Any]] {
        let out = try await call(binary, arguments)
        guard let data = out.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw Failure(message: "Claude Code's `\(arguments.joined(separator: " "))` answered something Lookout can't read.")
        }
        return list
    }

    @discardableResult
    private func call(_ binary: String, _ arguments: [String]) async throws -> String {
        let command = "`claude \(arguments.joined(separator: " "))`"
        let result: Output
        do {
            result = try await run(binary, arguments)
        } catch is CancellationError {
            throw Failure(message: "\(command) was stopped.")
        } catch {
            throw Failure(message: "\(command) failed: \(error.localizedDescription)")
        }
        guard result.status == 0 else {
            let said = (result.err.isEmpty ? result.out : result.err).trimmingCharacters(in: .whitespacesAndNewlines)
            throw Failure(message: "\(command) failed: \(said.isEmpty ? "exit \(result.status)" : said)")
        }
        return result.out
    }

    /// The real CLI, through `OneShot` (one deadline, SIGTERM then SIGKILL with the exit confirmed, the pipes drained and
    /// not waited on past a grace): started by `/usr/bin/env -i` with a clean environment (home, a plain PATH, the
    /// locale). Every run is tracked in `runs`, so quitting can stop them.
    static func oneShotRunner(timeout: TimeInterval = 120, runs: PluginRuns) -> Runner {
        { binary, arguments in
            guard !UnderTest.isRunning || binary.hasPrefix(FileManager.default.temporaryDirectory.path)
                    || !UnderTest.refuses("the Claude Code CLI (claude \(arguments.joined(separator: " ")))") else {
                throw Failure(message: "not under test")
            }
            let env = ProcessInfo.processInfo.environment
            var clean = ["HOME=\(NSHomeDirectory())", "PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LANG=en_US.UTF-8"]
            for name in ["USER", "LOGNAME", "TMPDIR"] { if let value = env[name] { clean.append("\(name)=\(value)") } }
            let handle = OneShot.Handle()
            guard runs.add(handle) else { throw CancellationError() }
            defer { runs.remove(handle) }
            let output = try await OneShot.run("/usr/bin/env", ["-i"] + clean + [binary] + arguments,
                                               cwd: URL(fileURLWithPath: NSHomeDirectory()), timeout: timeout, handle: handle)
            return Output(status: output.status, out: String(decoding: output.stdout, as: UTF8.self),
                          err: String(decoding: output.stderr, as: UTF8.self))
        }
    }
}

/// The installer's runs of the CLI under way. Quitting cancels them (each is stopped and its exit confirmed) and refuses
/// new ones.
final class PluginRuns: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [ObjectIdentifier: OneShot.Handle] = [:]
    private var closed = false

    init() {}

    func add(_ handle: OneShot.Handle) -> Bool {
        lock.withLock {
            guard !closed else { return false }
            handles[ObjectIdentifier(handle)] = handle
            return true
        }
    }

    func remove(_ handle: OneShot.Handle) {
        _ = lock.withLock { handles.removeValue(forKey: ObjectIdentifier(handle)) }
    }

    var active: Int { lock.withLock { handles.values.filter(\.isActive).count } }

    /// Cancels every run and waits (up to `within`) for their programs to be gone.
    func shutdown(within: TimeInterval = 3) {
        let all = lock.withLock { () -> [OneShot.Handle] in
            closed = true
            return Array(handles.values)
        }
        all.forEach { $0.cancel() }
        let until = Date().addingTimeInterval(within)
        while all.contains(where: \.isActive), Date() < until { usleep(10_000) }
    }
}

/// Who may make the relay key: switching the Router moves the generation on, and switching it off deletes the key under
/// the same lock, so a switch-on still under way (its install blocked, say) can't make the key again after the switch-off.
final class RelayKeyFence: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0

    init() {}

    var current: Int { lock.withLock { generation } }

    /// A new switch-on: what earlier ones do from now on is fenced off.
    func advance() -> Int { lock.withLock { generation += 1; return generation } }

    /// Switch-off: fences every switch-on so far and deletes the key, and every presence file written under it, at once
    /// and whatever comes after.
    func revoke(_ key: URL, presence: URL) {
        lock.withLock {
            generation += 1
            ClaudePlugin.removeKey(at: key)
            let fm = FileManager.default
            for file in (try? fm.contentsOfDirectory(at: presence, includingPropertiesForKeys: nil)) ?? [] {
                try? fm.removeItem(at: file)
            }
        }
    }

    /// Runs `body` only if no switch came after `generation`; a revocation waits for it to finish.
    @discardableResult
    func ifCurrent<T>(_ generation: Int, _ body: () throws -> T) rethrows -> T? {
        try lock.withLock { self.generation == generation ? try body() : nil }
    }
}

/// The key's file as last read: a key read once is used again while the file is the same one, unchanged.
struct RelayKeyCache: Equatable {
    var key: String
    /// `ClaudePlugin.keyID(of: key)`.
    var keyID: String
    var inode: UInt64
    var modified: timespec
    var size: Int64

    static func == (a: RelayKeyCache, b: RelayKeyCache) -> Bool {
        a.key == b.key && a.keyID == b.keyID && a.inode == b.inode && a.size == b.size
            && a.modified.tv_sec == b.modified.tv_sec && a.modified.tv_nsec == b.modified.tv_nsec
    }

    /// The file's identity now, without reading it; nil when it's gone.
    static func stamp(_ url: URL) -> (inode: UInt64, modified: timespec, size: Int64)? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return (UInt64(info.st_ino), info.st_mtimespec, Int64(info.st_size))
    }

    /// Reads the key (off the main thread, where it's called from a switch).
    static func load(_ url: URL) -> RelayKeyCache? {
        guard let stamp = stamp(url), let key = ClaudePlugin.key(at: url) else { return nil }
        return RelayKeyCache(key: key, keyID: ClaudePlugin.keyID(of: key), inode: stamp.inode, modified: stamp.modified, size: stamp.size)
    }

    func matches(_ url: URL) -> Bool {
        guard let now = Self.stamp(url) else { return false }
        return now.inode == inode && now.size == size && now.modified.tv_sec == modified.tv_sec && now.modified.tv_nsec == modified.tv_nsec
    }
}

extension ClaudePluginInstaller {
    /// The CLI as the app runs it: `oneShotRunner` with the app's own record of runs (stopped when it quits).
    static let processRunner: Runner = oneShotRunner(runs: .shared)
}

extension PluginRuns {
    static let shared = PluginRuns()
}

extension ClaudePlugin {
    /// `sessions(in:registry:keyID:alive:)` under the key named by the plugin's `config.json` beside the presence folder.
    /// Reads files: call it off the main thread.
    static func sessions(in presence: URL, registry: [Int32: [ClaudePeers.Registered]],
                         alive: (Int32) -> Bool = FormBridge.processAlive) -> Set<String> {
        sessions(in: presence, registry: registry, keyID: currentKeyID(beside: presence), alive: alive)
    }

    /// The id of the key the plugin's `config.json` (in the plugin folder beside `presence`) names, if it exists.
    static func currentKeyID(beside presence: URL) -> String? {
        let config = presence.deletingLastPathComponent().appendingPathComponent("claude-plugin/config.json")
        guard let data = try? Data(contentsOf: config), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let keyPath = obj["keyPath"] as? String, let key = key(at: URL(fileURLWithPath: keyPath)) else { return nil }
        return keyID(of: key)
    }

    /// The sessions the plugin runs in, for a presence folder of Lookout's: Claude Code's registry and the key are those
    /// its `config.json` (beside it, in the plugin's folder) names. None when that isn't written yet, or there's no key.
    /// Reads files: call it off the main thread.
    static func sessions(in presence: URL) -> Set<String> {
        let config = presence.deletingLastPathComponent().appendingPathComponent("claude-plugin/config.json")
        guard let data = try? Data(contentsOf: config), let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dir = obj["sessionsDir"] as? String else { return [] }
        return sessions(in: presence, registry: ClaudePeers.registry(dir: URL(fileURLWithPath: dir, isDirectory: true)))
    }
}

extension ClaudePlugin {
    /// The sessions whose plugin takes messages from its inbox (`RelayInbox`), a subset of `sessions`: a plugin of an older
    /// version doesn't say so in its presence file, and is reached over the peer channel. Reads files: call it off the main
    /// thread.
    static func inboxSessions(in presence: URL, registry: [Int32: [ClaudePeers.Registered]], keyID: String?, now: Date = leaseNow,
                              alive: (Int32) -> Bool = FormBridge.processAlive) -> Set<String> {
        sessions(with: inboxCapability, in: presence, registry: registry, keyID: keyID, now: now, alive: alive)
    }

    /// The sessions whose plugin says it has `capability`.
    static func sessions(with capability: String, in presence: URL, registry: [Int32: [ClaudePeers.Registered]], keyID: String?,
                         now: Date = leaseNow, alive: (Int32) -> Bool = FormBridge.processAlive) -> Set<String> {
        Set(live(in: presence, registry: registry, keyID: keyID, now: now, alive: alive)
            .filter { $0.value.capabilities?.contains(capability) == true }.keys)
    }
}

// MARK: - The direct way: an inbox per session

/// Delivery with no model: the signed text (the very text the peer channel would carry, so the plugin checks it the same way)
/// is written to `relay/<session id>/<nonce>.msg` under Application Support, atomically, and the plugin in that session, which
/// looks every half second, verifies it, submits it as the person's own words and answers with `<nonce>.ack` ("ok", or
/// "refused: why"). Lookout reads the ack and removes both files (the plugin cannot delete). A session whose plugin doesn't
/// answer in time is left to the peer channel; the nonce is the same, so if the plugin gets to it after all, whichever
/// arrives second is refused as a replay.
struct RelayInbox: Sendable {
    var root: URL
    /// How long the plugin has to answer.
    var timeout: TimeInterval = RelayInbox.wait

    enum Failure: Error, Equatable, LocalizedError {
        /// The plugin didn't answer in time: the message is withdrawn, and may go another way.
        case unanswered
        /// The plugin (or the check before writing) refused it: another way would be refused too.
        case refused(String)
        var errorDescription: String? {
            switch self {
            case .unanswered: "The session's plugin didn't pick the message up"
            case .refused(let why): "The session's plugin refused the message: \(why)"
            }
        }
    }

    /// `relay/` beside the presence folder, in Lookout's Application Support.
    static func root(besidePresence presence: URL) -> URL {
        presence.deletingLastPathComponent().appendingPathComponent("relay", isDirectory: true)
    }

    /// How long the plugin has to answer: it looks every 0.5 s, so this is a dozen looks.
    static let wait: TimeInterval = 6
    /// Files older than this are leftovers (a crash between writing and reading the ack): removed on the next delivery.
    static let leftover: TimeInterval = 15 * 60

    /// The target and the nonce in a signed text's header line.
    static func header(of text: String) -> (target: String, nonce: String)? {
        guard let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              line.hasSuffix("⟧") else { return nil }
        for (prefix, count) in [("⟦lookout v1 ", 4), ("⟦lookout v2 ", 6)] where line.hasPrefix(prefix) {
            let fields = line.dropFirst(prefix.count).dropLast().split(separator: " ")
            guard fields.count == count else { return nil }
            return (String(fields[0]), String(fields[1]))
        }
        return nil
    }

    private static func safe(_ name: String) -> Bool {
        !name.isEmpty && name.count <= 128 && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    func folder(for session: String) -> URL { root.appendingPathComponent(session, isDirectory: true) }

    /// Writes `text` for `session` and waits for the plugin's answer. Throws `unanswered` when there's none within `timeout`
    /// (the message is withdrawn first), `refused` when the plugin says no. Returns the plugin's answer: "ok", with what it
    /// applied after it when the message carried settings ("ok model=opus effort=high").
    /// `gate` says, on the main actor and right before the message is written (nothing awaited between the two), why it
    /// may no longer go: a reason refuses it, unwritten.
    @discardableResult
    func deliver(_ text: String, to session: String, interval: TimeInterval = 0.03,
                 gate: (@MainActor () -> String?)? = nil) async throws -> String {
        guard let header = Self.header(of: text), header.target == session, Self.safe(session), Self.safe(header.nonce) else {
            throw Failure.refused("not a message signed for this session")
        }
        let dir = folder(for: session)
        let message = dir.appendingPathComponent("\(header.nonce).msg"), ack = dir.appendingPathComponent("\(header.nonce).ack")
        let fm = FileManager.default
        if let gate {
            try await OffMain.run { Swift.Result { try Self.sweep(dir) } }.get()
            try await MainActor.run {
                if let refusal = gate() { throw Failure.refused(refusal) }
                try PrivateFile.write(Data(text.utf8), to: message)
            }
        } else {
            try await OffMain.run { Swift.Result { try Self.sweep(dir); try PrivateFile.write(Data(text.utf8), to: message) } }.get()
        }
        func withdraw() { try? fm.removeItem(at: message); try? fm.removeItem(at: ack) }
        func answer() -> String? {
            guard let data = try? Data(contentsOf: ack), let text = String(data: data, encoding: .utf8) else { return nil }
            // An empty file is an answer still being written (it is created, then filled): not an answer yet.
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func outcome(_ reply: String) throws -> String {
            withdraw()
            if reply == "ok" || reply.hasPrefix("ok ") { return reply }
            throw Failure.refused(reply.hasPrefix("refused: ") ? String(reply.dropFirst("refused: ".count)) : reply)
        }
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while Date() < deadline {
                if let reply = answer() { return try outcome(reply) }
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        } catch is CancellationError {
            withdraw()
            throw CancellationError()
        }
        // Withdrawn, then looked at once more: an answer that came as the file went counts.
        try? fm.removeItem(at: message)
        if let reply = answer() { return try outcome(reply) }
        withdraw()
        throw Failure.unanswered
    }

    /// Removes what's left of earlier deliveries in `dir` (older than `leftover`), and makes the folder private.
    private static func sweep(_ dir: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let old = Date().addingTimeInterval(-leftover)
        for url in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < old { try? fm.removeItem(at: url) }
        }
    }
}

extension RouterPaths {
    /// The folder of per-session inboxes (`RelayInbox`), beside the plugin's presence folder.
    var relay: URL { RelayInbox.root(besidePresence: pluginSessions) }
}

extension Store {
    /// The inbox to deliver to `cli` through, when that session's plugin takes messages that way (it says so in its presence
    /// file, under the key held now); nil sends them over the peer channel.
    func relayInbox(for cli: String) async -> RelayInbox? {
        guard let paths = routerFiles, let keyID = relayKeyCache?.keyID else { return nil }
        let capable = await OffMain.run {
            ClaudePlugin.inboxSessions(in: paths.pluginSessions,
                                       registry: ClaudePeers.registry(dir: paths.claudeDir.appendingPathComponent("sessions", isDirectory: true)),
                                       keyID: keyID).contains(cli)
        }
        return capable ? RelayInbox(root: paths.relay) : nil
    }

    /// The inbox for a signed text, by the session it is signed for (its CLI session id): callers hold the peer's name, which
    /// is not the id the plugin's presence and inbox folder go by.
    func relayInbox(forSigned text: String) async -> RelayInbox? {
        guard let target = RelayInbox.header(of: text)?.target else { return nil }
        return await relayInbox(for: target)
    }

    /// Whether `cli`'s plugin applies a model and an effort carried in a message (it says `settings-v1`, under the key held
    /// now). An older plugin doesn't: nothing with settings is sent to it.
    func supportsSettings(_ cli: String) async -> Bool {
        guard let paths = routerFiles, let keyID = relayKeyCache?.keyID else { return false }
        return await OffMain.run {
            ClaudePlugin.sessions(with: ClaudePlugin.settingsCapability, in: paths.pluginSessions,
                                  registry: ClaudePeers.registry(dir: paths.claudeDir.appendingPathComponent("sessions", isDirectory: true)),
                                  keyID: keyID).contains(cli)
        }
    }
}

extension RelaySigner {
    /// `mac` over a body given as text (its UTF-8 bytes).
    static func mac(key: String, target: String, nonce: String, ts: String, body: String) -> String {
        mac(key: key, target: target, nonce: nonce, ts: ts, body: Data(body.utf8))
    }
}

extension RelaySigner {
    /// A text with every signed message in it shown as its body: the header line goes, and the base64 line after it is
    /// decoded (left as it is when it isn't base64 of UTF-8). For the chat and receipts, which never show the wire.
    static func readable(_ text: String) -> String {
        guard text.contains("⟦lookout v1 ") else { return text }
        var lines = text.components(separatedBy: "\n")
        var i = 0
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("⟦lookout v1 "), line.hasSuffix("⟧") else { i += 1; continue }
            lines.remove(at: i)
            if i < lines.count, let data = Data(base64Encoded: lines[i].trimmingCharacters(in: .whitespaces)),
               let body = String(data: data, encoding: .utf8) {
                lines[i] = body
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
