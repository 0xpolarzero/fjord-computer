import type { EngineInterface, Register } from 'claude-code'

// Fjord's Router relays what the person writes to this session. The message arrives on the peer channel,
// signed by the Fjord app with a key only it holds (a file of Fjord's own, readable by the person
// alone, never in this folder: Claude Code copies an installed plugin's folder into its cache). A valid one, addressed
// to this session, fresh and never seen before, is taken off the peer channel and submitted as the person's own words.
// Anything else passes on untouched, as the peer message it is.
//
// The wire format: a header line, then the body's UTF-8 bytes in base64 on one line (so the peer channel's escaping and
// any Unicode normalization can't touch them):
//   ⟦fjord v1 <target session id> <nonce> <ms since 1970> <hex HMAC-SHA256>⟧\n<base64 body>
// The MAC covers the UTF-8 bytes of "v1\n<target>\n<nonce>\n<ms>\n" followed by the body's own UTF-8 bytes.
//
// Two ways in, one check. The peer channel (`session.receive`) is the original way and stays as the fallback for a
// Fjord that can't reach this plugin directly. The inbox is the direct way, with no model in between:
// Fjord writes the very same signed text to `<inboxDir>/<session id>/<nonce>.msg` (atomically: a dot-file
// renamed into place), the plugin polls that folder every half second, runs the same check, and answers with
// `<nonce>.ack` beside it ("ok", or "refused: why"). Fjord reads the ack and deletes both files; the plugin
// has no way to delete, and needs none. Presence files list `capabilities`, so Fjord knows how a
// session can be reached.
//
// `settings-v1`: a v2 message carries the model and effort the session should use, inside the signed bytes:
//   ⟦fjord v2 <target> <nonce> <ms> <model|-> <effort|-> <hex HMAC-SHA256>⟧\n<base64 body>
// with the MAC over "v2\n<target>\n<nonce>\n<ms>\n<model|->\n<effort|->\n" and the body. A plugin without the capability
// sees an unknown header (unsigned) and ignores it; Fjord only sends v2 to a plugin that advertises `settings-v1`.
// From the inbox (never the peer channel, whose hook the turn waits on), the plugin sets the model, then the effort (a
// model switch resets the effort), with `/model` and `/effort` run for this session only, and only then submits the
// text, so the turn it starts uses them. The ack says what happened: "ok model=opus effort=high", or "model=error:why".
//
// `abort-v1`: Fjord can take back a delivery it made, with a control file in the same inbox, signed the same way:
//   ⟦fjord abort v1 <target> <nonce> <ms> <nonce of the delivery> <hex HMAC-SHA256>⟧
// with the MAC over "abort-v1\n<target>\n<nonce>\n<ms>\n<nonce of the delivery>\n" (no body). Its own nonce is claimed as a
// delivery's is (no replay). This copy remembers each delivery it submitted and the turn it started (the next main turn
// whose text is that delivery's, or holds it with other deliveries), and answers in the ack, "ok " and how:
//   before-start  it never started: not seen yet (it will be refused when it comes), or queued behind a running turn, its
//                 turn then ended the moment it starts (unless Claude Code reads it together with words of the
//                 person's own: those are never stopped)
//   aborted       its turn was running, and is stopped: the tools it is running are answered at once (else an abort
//                 sends a running Bash command to the background, and its end wakes the session to carry on), then
//                 $.turn.abort; a notification from one of its tools after that is dropped, so the session doesn't take
//                 the cancelled request up again. The command's process itself runs to its end: no hook can stop it.
//   together      its turn also holds words of the person's own: it isn't stopped, so neither are they
//   too-late      its turn is over
//   unknown       this copy never saw it, but one did (a reload since): it can't tell
// Nothing an aborted turn already did is undone, and the words stay in the session's history: Claude Code has no way to
// take a submitted prompt back out.
//
// Fjord writes this file; edits are overwritten.

const HEADER = /(?:^|\n)⟦fjord (?:v1 (\S+) (\S+) (\d+)|v2 (\S+) (\S+) (\d+) (\S+) (\S+)) ([0-9a-f]{64})⟧\n/
const BASE64 = /^[A-Za-z0-9+/]*={0,2}$/
const CLOSE = '</cross-session-message>'
const WINDOW_MS = 10 * 60 * 1000
const NONCE = 'nonce.'
export const CAPABILITIES = ['inbox-v1', 'settings-v1', 'abort-v1']
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

const ABORT = /^⟦fjord abort v1 (\S+) (\S+) (\d+) (\S+) ([0-9a-f]{64})⟧\n?/

/** What an abort's MAC covers: its kind, the target, its nonce, its time and the delivery it takes back, one per line. */
export const abortMacInput = (target: string, nonce: string, ts: string, cancels: string) =>
  enc.encode(`abort-v1\n${target}\n${nonce}\n${ts}\n${cancels}\n`)

/** An abort's fields; undefined for anything else. */
export const parseAbort = (text: string) => {
  const m = ABORT.exec(text)
  return m ? { target: m[1], nonce: m[2], ts: m[3], cancels: m[4], mac: m[5] } : undefined
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

/** Where Fjord keeps the key and the presence files, and Claude Code its registry of processes, as absolute paths (a
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
 * and start time) and to the key Fjord holds now, so Fjord can tell a live session from one that crashed, was resumed
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

/** Claims a nonce: false when it was claimed before. Each nonce is a key of its own in the store (it outlives reloads and
 * restarts), kept while its message's time is inside the window: past it the message is refused as stale anyway. */
const claim = ($: EngineInterface, nonce: string, ts: number, now: number) =>
  exclusive(async () => {
    if ((await $.store.get(NONCE + nonce)) !== undefined) return false
    await $.store.set(NONCE + nonce, ts)
    for (const name of await $.store.keys()) {
      if (!name.startsWith(NONCE)) continue
      const at = Number(await $.store.get(name))
      if (!(Math.abs(now - at) < WINDOW_MS)) await $.store.delete(name)
    }
    return true
  })

/** A delivery this copy submitted, by its nonce: its words and when, the turn it started once one did (and whether that
 * turn holds words of the person's own too, or is still starting), and whether that turn is over or was taken back before
 * it began. Kept for the window an abort is taken in, the latest few at most. */
type Sent = { body: string; at: number; turnId?: string; mixed?: boolean; starting?: boolean; ended?: boolean; cancelled?: boolean }
const sent = new Map<string, Sent>()
const SENT_KEPT = 50
/** A body this long is told apart inside a turn that holds other words too; a shorter one only as the whole turn. */
const DISTINCT = 24
/** The main loop's turn under way, by `turn.start` and `turn.complete`. */
let running: string | undefined
/** In a turn a delivery started: the tool calls under way, each with what cuts it short, the ids of every call made, and
 * the subagents it spawned. */
const calls = new Map<string, { cuts: Set<() => void>; ids: Set<string>; agents: Set<string> }>()
/** The tool calls of turns taken back, with when: a notification naming only them (a background command ending) is
 * dropped. Kept an hour. */
const quiet = new Map<string, number>()
const QUIET_MS = 60 * 60 * 1000

/** Forgets every delivery and turn (tests: each starts a fresh copy's memory). */
export const forget = () => {
  sent.clear()
  calls.clear()
  quiet.clear()
  running = undefined
}

/** Stops what a turn's tools are doing, and keeps their notifications out from now on. */
const silence = (turnId: string, now: number) => {
  const turn = calls.get(turnId)
  if (!turn) return
  for (const cut of turn.cuts) cut()
  for (const id of turn.ids) quiet.set(id, now)
  calls.delete(turnId)
}

/** Forgets deliveries past the window (an abort of one is refused as stale anyway) and notifications kept long enough. */
const prune = (now: number) => {
  for (const [nonce, s] of sent) if (!(Math.abs(now - s.at) < WINDOW_MS)) sent.delete(nonce)
  for (const [id, at] of quiet) if (!(Math.abs(now - at) < QUIET_MS)) quiet.delete(id)
}

const remember = (nonce: string, body: string, now: number) => {
  prune(now)
  sent.set(nonce, { body, at: now })
  while (sent.size > SENT_KEPT) sent.delete(sent.keys().next().value as string)
}

/** Submits a delivery's words; one a hook drops, or that fails, started nothing and is forgotten (else a later turn of the
 * person's own could be taken for its turn). */
const submit = ($: EngineInterface, nonce: string, body: string) => {
  const forgotten = () => {
    if (sent.get(nonce)?.turnId === undefined) sent.delete(nonce)
  }
  void $.prompt.submit({ text: body, asUser: true }).then((r) => {
    if (r && 'drop' in r && r.drop !== undefined) forgotten()
  }, forgotten)
}

/** The deliveries a main turn starts with: each one waiting whose words are the turn's text, or, when Claude Code read
 * queued prompts together, whose (distinctive) words it holds. `mixed`: the turn holds words of no delivery too (the
 * person's own). */
const startedBy = (text: string, now: number) => {
  prune(now)
  const said = text.trim()
  const mine: Sent[] = []
  let rest = said
  for (const s of sent.values()) {
    if (s.turnId !== undefined) continue
    const body = s.body.trim()
    if (!body) continue
    if (said === body) return { mine: [s], mixed: false }
    if (body.length >= DISTINCT && rest.includes(body)) {
      mine.push(s)
      rest = rest.replace(body, '')
    }
  }
  return { mine, mixed: rest.trim() !== '' }
}

/** Takes back the delivery `nonce`, as far as can still be: the ack's word for how. */
export async function cancel($: EngineInterface, nonce: string, ts: number, now: number) {
  prune(now)
  const s = sent.get(nonce)
  if (!s) {
    // Never submitted here: claimed now, it is refused when it comes; claimed already, an earlier copy took it.
    return (await claim($, nonce, ts, now)) ? 'before-start' : 'unknown'
  }
  if (s.ended) return 'too-late'
  if (s.mixed) return 'together'
  // Not started, or starting (its turn.start hasn't finished): ended as turn.start finishes.
  if (s.turnId === undefined || s.starting) {
    s.cancelled = true
    return 'before-start'
  }
  if (running !== s.turnId) return 'too-late'
  try {
    await $.turn.abort({ turnId: s.turnId })
  } catch {
    return 'too-late'
  }
  // Only once the abort is taken: the tools it was running, and what they would say afterwards.
  silence(s.turnId, now)
  for (const other of sent.values()) if (other.turnId === s.turnId) other.ended = true
  return 'aborted'
}

/** Checks an abort the way a delivery is checked (its signature, its session, its time, its nonce never seen) and acts on
 * it: the ack's text. */
export async function control($: EngineInterface, text: string) {
  const abort = parseAbort(text)
  if (!abort) return 'refused: unsigned'
  const { keyPath } = await config($)
  if (!keyPath) return 'refused: no key configured'
  const key = (await $.fs.read(keyPath)).trim()
  const expected = await hmac(enc.encode(key), abortMacInput(abort.target, abort.nonce, abort.ts, abort.cancels))
  const now = await $.clock.now()
  const ts = Number(abort.ts)
  if (!same(expected, abort.mac)) return 'refused: bad signature'
  if (abort.target !== (await $.session.id())) return 'refused: addressed to another session'
  if (!(Math.abs(now - ts) < WINDOW_MS)) return 'refused: stale'
  if (!(await claim($, abort.nonce, ts, now))) return 'refused: already delivered'
  return `ok ${await cancel($, abort.cancels, ts, now)}`
}

/** Checks a signed text the way both ways in must, and submits it as the person's own words. `unsigned` means it isn't
 * Fjord's at all (the peer channel then passes it on); anything else is a refusal with its reason. */
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
  if (!(await claim($, signed.nonce, ts, now))) return { ok: false, reason: 'already delivered' }
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
  remember(signed.nonce, body, now)
  submit($, signed.nonce, body)
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
      if (parseAbort(text)) {
        const reply = await control($, text).catch((error) => `refused: ${String(error?.message ?? error)}`)
        await $.fs.write(`${dir}/${name.slice(0, -4)}.ack`, `${reply}\n`)
        continue
      }
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
    return { consumed: 'relayed by Fjord as the person’s own message' }
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
    running = e.turnId
    const now = await $.clock.now()
    const { mine, mixed } = startedBy(e.text, now)
    for (const s of mine) Object.assign(s, { turnId: e.turnId, mixed, starting: true })
    if (mine.length) calls.set(e.turnId, { cuts: new Set(), ids: new Set(), agents: new Set() })
    try {
      await mark($).catch(() => undefined)
      return await next(e)
    } finally {
      for (const s of mine) s.starting = false
      // Taken back while it waited its turn (or as it started), and wholly Fjord's: it ends as it begins.
      // One that holds words of the person's own isn't stopped.
      if (!mixed && mine.some((s) => s.cancelled)) {
        for (const s of mine) s.ended = true
        await $.turn.abort({ turnId: e.turnId }).catch(() => undefined)
        silence(e.turnId, now)
      }
    }
  })
  on('turn.complete', async ($, e, next) => {
    if (e.agentId === undefined) {
      for (const s of sent.values()) if (s.turnId === e.turnId) s.ended = true
      if (running === e.turnId) running = undefined
      calls.delete(e.turnId)
    }
    return next(e)
  })
  // The subagents a delivery's turn spawns are its own: their tool calls are cut with its.
  on('agent.spawn', async ($, e, next) => {
    const turn = running === undefined ? undefined : calls.get(running)
    const spawned = await next(e)
    const id = (spawned as { agentId?: unknown })?.agentId
    if (turn && typeof id === 'string') turn.agents.add(id)
    return spawned
  }).catch(($, e, next) => next(e))
  // A tool call of a turn a delivery started (on the main loop, or in a subagent it spawned) can be cut short by a cancel:
  // answered before what runs beneath is done. Any other call (a background agent of an earlier turn's) passes straight
  // through.
  on('tool.call', async ($, e, next) => {
    const turn = running === undefined ? undefined : calls.get(running)
    if (!turn || (e.agentId !== undefined && !turn.agents.has(e.agentId))) return next(e)
    if (e.tool_use_id) turn.ids.add(e.tool_use_id)
    let cut = () => {}
    const stopped = new Promise<'cut'>((resolve) => {
      cut = () => resolve('cut')
    })
    turn.cuts.add(cut)
    try {
      const done = await Promise.race([next(e), stopped])
      return done === 'cut' ? { deny: 'Stopped: the person cancelled this message from Fjord.' } : done
    } finally {
      turn.cuts.delete(cut)
    }
  }).catch(($, e, next) => next(e))
  // A notification only of tasks of a turn taken back is dropped; one that tells of others too goes as it is.
  on('prompt.submit', async ($, e, next) => {
    if (e.origin.kind === 'task-notification' && quiet.size) {
      const ids = [...e.text.matchAll(/<tool-use-id>([^<\s]+)<\/tool-use-id>/g)].map((m) => m[1])
      if (ids.length && ids.every((id) => quiet.has(id))) {
        return { drop: 'A task of a message cancelled from Fjord ended: not taken up again.' }
      }
    }
    return next(e)
  })
  on('session.end', async ($, e, next) => {
    await unmark($).catch(() => undefined)
    return next(e)
  })
}
