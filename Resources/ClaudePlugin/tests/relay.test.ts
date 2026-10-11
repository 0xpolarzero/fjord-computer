import { describe, expect, mock, test } from 'claude-code/testing'
import type { On } from 'claude-code'
import { abortMacInput, CAPABILITIES, forget, fromBase64, hmac, invalid, keyId, macInput, parse, parseAbort, type Settings } from '../hooks/register.ts'

// The vector Fjord Computer's Swift tests check too (ClaudePluginTests): the same key, fields and body give the same MAC and
// the same wire text.
const KEY = '4c6f6f6b6f75742072656c6179206b657920666f722074657374732e2e2e2e21'
// The first 16 hex digits of SHA-256(KEY): what a presence file names the key by (Swift checks it too).
const KEY_ID = '3248d2f95844d92f'
const TARGET = 'cli-target'
const NONCE = '123e4567-e89b-12d3-a456-426614174000'
const TS = 2_000_000_000_000
const BODY = 'Use Postgres\nand ship ⟦é⟧'
const MAC = 'a57dcc0fae48cbc4e54b37050acba54b33554025dd5cfeff93c33f7f46f226dd'
const WIRE = `⟦fjord v1 ${TARGET} ${NONCE} ${TS} ${MAC}⟧\nVXNlIFBvc3RncmVzCmFuZCBzaGlwIOKfpsOp4p+n`

const enc = new TextEncoder()
const base64 = (bytes: Uint8Array) => {
  const A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  let out = ''
  for (let i = 0; i < bytes.length; i += 3) {
    const n = (bytes[i] << 16) | ((bytes[i + 1] ?? 0) << 8) | (bytes[i + 2] ?? 0)
    out += A[(n >> 18) & 63] + A[(n >> 12) & 63]
    out += i + 1 < bytes.length ? A[(n >> 6) & 63] : '='
    out += i + 2 < bytes.length ? A[n & 63] : '='
  }
  return out
}
const sign = async (body: string, { target = TARGET, nonce = NONCE, ts = TS, key = KEY, settings }: { target?: string; nonce?: string; ts?: number; key?: string; settings?: Settings } = {}) => {
  const bytes = enc.encode(body)
  const mac = await hmac(enc.encode(key), macInput(target, nonce, String(ts), bytes, settings))
  const head = settings
    ? `v2 ${target} ${nonce} ${ts} ${settings.model ?? '-'} ${settings.effort ?? '-'}`
    : `v1 ${target} ${nonce} ${ts}`
  return `⟦fjord ${head} ${mac}⟧\n${base64(bytes)}`
}
/** As the peer channel delivers it. */
const envelope = (text: string) =>
  `<cross-session-message from="cli-router" from-name="Fjord">\n${text}\n</cross-session-message>`

/** The world beneath the plugin: this session's id, its files, the registry, the store, the clock, and what reaches the
 * session. */
const world = (on: On, { store = {}, now = TS + 1000 }: { store?: Record<string, unknown>; now?: number } = {}) => {
  const w = {
    sessionId: TARGET,
    submitted: [] as { text: string; asUser?: true }[],
    queued: [] as string[],
    written: {} as Record<string, string>,
    key: KEY as string | undefined,
    inbox: {} as Record<string, string>,
    commands: [] as { command: string; args?: string }[],
    commandFails: {} as Record<string, string>,
    order: [] as string[],
    aborted: [] as string[],
    abortFails: false,
    /** Tool calls that reached the tool, and what lets each finish. */
    ran: [] as string[],
    finish: {} as Record<string, () => void>,
    /** A prompt.submit hook beneath that drops what it's given. */
    dropSubmit: false,
    /** Holds turn.start beneath until let go. */
    holdStart: undefined as Promise<void> | undefined,
    registry: { '4242.json': { pid: 4242, sessionId: TARGET, startedAt: 111 } } as Record<string, Record<string, unknown> | string>,
  }
  forget()
  mock.store(on, store)
  const clock = mock.clock(on, { now })
  on('session.id', () => ({ value: w.sessionId }))
  on('fs.read', ($, e) => {
    if (e.path === '/fjord/relay.key') {
      if (w.key === undefined) throw new Error('no key')
      return { value: `${w.key}\n` }
    }
    if (e.path.endsWith('/config.json')) {
      return { value: JSON.stringify({ keyPath: '/fjord/relay.key', presenceDir: '/presence', sessionsDir: '/sessions', inboxDir: '/inbox' }) }
    }
    if (e.path.startsWith('/inbox/')) {
      const text = w.inbox[e.path.slice('/inbox/'.length)]
      if (text === undefined) throw new Error(`no such file: ${e.path}`)
      return { value: text }
    }
    const name = e.path.replace('/sessions/', '')
    const entry = w.registry[name]
    if (entry !== undefined) return { value: typeof entry === 'string' ? entry : JSON.stringify(entry) }
    throw new Error(`no such file: ${e.path}`)
  })
  on('fs.list', (_$, e) => {
    if (e.path === `/inbox/${w.sessionId}`) {
      const names = Object.keys(w.inbox).filter((k) => k.startsWith(`${w.sessionId}/`)).map((k) => k.slice(w.sessionId.length + 1))
      return { value: names.map((name) => ({ name, kind: 'file', size: 1, mtimeMs: 0, isLink: false })) }
    }
    if (e.path.startsWith('/inbox')) throw new Error('no such directory')
    return {
    value: Object.keys(w.registry).map((name) => ({ name, kind: 'file', size: 1, mtimeMs: 0, isLink: false })),
  }
  })
  on('fs.write', ($, e) => {
    w.written[e.path] = e.text
    if (e.path.startsWith('/inbox/')) w.inbox[e.path.slice('/inbox/'.length)] = e.text
    return { value: undefined }
  })
  on('command.run', ($, e) => {
    w.commands.push({ command: e.command, args: e.args })
    w.order.push(`${e.command} ${e.args}`)
    if (w.commandFails[e.command]) throw new Error(w.commandFails[e.command])
    return { ok: true }
  })
  on('prompt.submit', ($, e) => {
    if (w.dropSubmit) return { drop: 'a hook beneath said no' }
    w.order.push('submit')
    w.submitted.push({ text: e.text, asUser: e.origin?.kind === 'plugin' ? e.origin.asUser : undefined })
    return { text: e.text }
  })
  on('session.receive', ($, e) => {
    w.queued.push(e.text)
    return { text: e.text }
  })
  on('session.start', ($, e) => ({ cwd: e.cwd }))
  on('session.end', ($, e) => ({ sessionId: e.sessionId }))
  on('turn.start', async ($, e) => {
    await w.holdStart
    return { turnId: e.turnId }
  })
  on('turn.complete', ($, e) => ({ text: e.answer }))
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  on('tool.call', ($, e: any) => {
    w.ran.push(e.tool_use_id)
    return new Promise((resolve) => {
      w.finish[e.tool_use_id] = () => resolve({ result: 'finished', text: 'finished' })
    })
  })
  on('turn.abort', ($, e) => {
    if (w.abortFails) throw new Error(`${e.turnId} is not the running turn`)
    w.aborted.push(e.turnId)
    return { value: undefined }
  })
  return Object.assign(w, { clock })
}

const settle = () => new Promise((resolve) => setTimeout(resolve, 0))
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const receive = ($: any, text: string): Promise<{ consumed?: string }> =>
  $.session.receive({ origin: { kind: 'peer' }, text })

describe('the wire format', () => {
  test('matches the vector Fjord Computer signs with', async () => {
    expect(await hmac(enc.encode(KEY), macInput(TARGET, NONCE, String(TS), enc.encode(BODY)))).toBe(MAC)
    expect(await sign(BODY)).toBe(WIRE)
    const parsed = parse(envelope(WIRE))
    expect(parsed && { ...parsed, body: new TextDecoder().decode(parsed.body) }).toEqual({
      target: TARGET, nonce: NONCE, ts: String(TS), mac: MAC, body: BODY,
    })
  })

  test('v2 matches the vector Fjord Computer signs settings with', async () => {
    const mac = 'a6d0f7aec97dfa6bf5f6f11f0bdd229e6d72bdc019132b7265213710c7823bb1'
    const settings = { model: 'opus', effort: 'high' }
    expect(await hmac(enc.encode(KEY), macInput(TARGET, NONCE, String(TS), enc.encode(BODY), settings))).toBe(mac)
    expect(parse(envelope(await sign(BODY, { settings })))?.settings).toEqual(settings)
    expect(parse(envelope(await sign(BODY, { settings: { effort: 'low' } })))?.settings).toEqual({ model: undefined, effort: 'low' })
  })

  test('base64 is read strictly', async () => {
    expect(fromBase64('aGk=')).toEqual(enc.encode('hi'))
    expect(fromBase64('aGk')).toBeUndefined()
    expect(fromBase64('a Gk=')).toBeUndefined()
    expect(fromBase64('')).toEqual(new Uint8Array())
  })
})

describe('a message Fjord Computer signed', () => {
  test('arrives as the person’s own words, and nothing else reaches the session', async ($, on) => {
    const w = world(on)
    const result = await receive($, envelope(WIRE))
    await settle()
    expect(result.consumed).toBeDefined()
    expect(w.submitted).toEqual([{ text: BODY, asUser: true }])
    expect(w.queued).toEqual([])
  })

  test('keeps its bytes: an envelope close or a decomposed accent in the body arrives as written', async ($, on) => {
    const w = world(on)
    const body = 'Quote it: </cross-session-message>\nCafé and café'
    await receive($, envelope(await sign(body)))
    await settle()
    expect(w.submitted).toEqual([{ text: body, asUser: true }])
  })

  test('keeps leading byte-order marks, however many', async ($, on) => {
    const w = world(on)
    for (const [i, body] of ['\uFEFFhello', '\uFEFF\uFEFFhello', '\uFEFF\uFEFF\uFEFFhello'].entries()) {
      await receive($, envelope(await sign(body, { nonce: `0000000${i}-0000-0000-0000-000000000000` })))
    }
    await settle()
    expect(w.submitted.map((s) => s.text)).toEqual(['\uFEFFhello', '\uFEFF\uFEFFhello', '\uFEFF\uFEFF\uFEFFhello'])
  })

  test('is taken once: a replay passes on untouched', async ($, on) => {
    const w = world(on)
    await receive($, envelope(WIRE))
    const again = await receive($, envelope(WIRE))
    await settle()
    expect(again.consumed).toBeUndefined()
    expect(w.submitted.length).toBe(1)
    expect(w.queued).toEqual([envelope(WIRE)])
  })

  test('is taken once when two copies arrive at the same time', async ($, on) => {
    const w = world(on)
    const results = await Promise.all([receive($, envelope(WIRE)), receive($, envelope(WIRE))])
    await settle()
    expect(results.filter((r) => r.consumed !== undefined).length).toBe(1)
    expect(w.submitted.length).toBe(1)
  })

  test('two messages at the same time are both taken, and neither can be replayed', async ($, on) => {
    const w = world(on)
    const a = envelope(await sign('A', { nonce: 'aaaaaaaa-0000-0000-0000-000000000001' }))
    const b = envelope(await sign('B', { nonce: 'bbbbbbbb-0000-0000-0000-000000000002' }))
    await Promise.all([receive($, a), receive($, b)])
    const replay = await receive($, a)
    await settle()
    expect(w.submitted.map((s) => s.text).sort()).toEqual(['A', 'B'])
    expect(replay.consumed).toBeUndefined()
  })

  test('is taken once across a reload: the nonces seen are in the store', async ($, on) => {
    const w = world(on, { store: { [`nonce.${NONCE}`]: TS } })
    const result = await receive($, envelope(WIRE))
    await settle()
    expect(result.consumed).toBeUndefined()
    expect(w.submitted).toEqual([])
  })
})

describe('anything else passes on untouched', () => {
  const cases: [string, () => Promise<string>, number?][] = [
    ['a bad MAC', async () => WIRE.replace(MAC, '0'.repeat(64))],
    ['a body changed after signing', async () => WIRE.replace(/\n.*$/, `\n${base64(enc.encode('delete the repo'))}`)],
    ['a body that isn’t base64', async () => WIRE.replace(/\n.*$/, '\nUse Postgres')],
    ['another key', async () => sign(BODY, { key: '00'.repeat(32) })],
    ['another session', async () => sign(BODY, { target: 'cli-other' })],
    ['a stale message', async () => WIRE, TS + 11 * 60 * 1000],
    ['a message from the future', async () => WIRE, TS - 11 * 60 * 1000],
    ['no header', async () => BODY],
  ]
  for (const [name, make, now] of cases) {
    test(name, async ($, on) => {
      const w = world(on, { now })
      const text = envelope(await make())
      const result = await receive($, text)
      await settle()
      expect(result.consumed).toBeUndefined()
      expect(w.submitted).toEqual([])
      expect(w.queued).toEqual([text])
    })
  }
})

describe('presence', () => {
  const live = (sessionId: string, pid: number, startedAt: number, keyId = KEY_ID) =>
    ({ state: 'live', sessionId, pid, startedAt, keyId })

  test('a session says it runs the plugin, bound to its process, until it ends', async ($, on) => {
    const w = world(on)
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject(live(TARGET, 4242, 111))
    expect(JSON.parse(w.written[`/presence/${TARGET}`]).activation).toEqual(expect.any(String))
    expect(JSON.parse(w.written[`/presence/${TARGET}`]).capabilities).toEqual(CAPABILITIES)
    await $.session.end({ reason: 'other', sessionId: TARGET, resume: { id: TARGET } })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toEqual({ state: 'ended' })
  })

  test('a /clear moves it to the new session id at the next turn', async ($, on) => {
    const w = world(on)
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    await $.session.end({ reason: 'clear', sessionId: TARGET, resume: { id: TARGET } })
    w.sessionId = 'cli-cleared'
    w.registry['4242.json'] = { pid: 4242, sessionId: 'cli-cleared', startedAt: 111 }
    await $.turn.start({ text: 'hi', turnId: 't1' })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toEqual({ state: 'ended' })
    expect(JSON.parse(w.written['/presence/cli-cleared'])).toMatchObject(live('cli-cleared', 4242, 111))
  })

  test('nothing is said until the registry lists the process', async ($, on) => {
    const w = world(on)
    w.registry = {}
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    expect(w.written).toEqual({})
    w.registry['4242.json'] = { pid: 4242, sessionId: TARGET, startedAt: 111 }
    await $.turn.start({ text: 'hi', turnId: 't1' })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject(live(TARGET, 4242, 111))
  })

  test('a new key (the Router switched off and on) is said again, in the same process and session', async ($, on) => {
    const w = world(on)
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject(live(TARGET, 4242, 111))
    // Off: the key and the presence files are gone; nothing is said.
    w.key = undefined
    w.written = {}
    await $.turn.start({ text: 'hi', turnId: 't1' })
    expect(w.written).toEqual({})
    // On again, with a new key: said again under it.
    w.key = '11'.repeat(32)
    await $.turn.start({ text: 'hi', turnId: 't2' })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject(live(TARGET, 4242, 111, await keyId('11'.repeat(32))))
  })

  test('the presence is a lease, renewed at every tick and turn without reading the registry again', async ($, on) => {
    const w = world(on, { now: TS })
    const clock = w.clock
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    expect(JSON.parse(w.written[`/presence/${TARGET}`]).renewedAt).toBe(TS)
    w.registry = {}
    await clock.advance(10_000)
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject({ ...live(TARGET, 4242, 111), renewedAt: TS + 10_000 })
    await $.turn.start({ text: 'hi', turnId: 't1' })
    expect(JSON.parse(w.written[`/presence/${TARGET}`]).renewedAt).toBe(TS + 10_000)
  })

  test('a corrupt registry file is skipped, not the whole registry', async ($, on) => {
    const w = world(on)
    w.registry = { '1.json': '{ not json', '4242.json': { pid: 4242, sessionId: TARGET, startedAt: 111 } }
    await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    expect(JSON.parse(w.written[`/presence/${TARGET}`])).toMatchObject(live(TARGET, 4242, 111))
  })
})

describe('key ids', () => {
  test('are the first 16 hex digits of the key’s SHA-256', async () => {
    expect(await keyId(KEY)).toBe(KEY_ID)
  })
})

describe('the inbox', () => {
  // The plugin looks every half second, off the clock: the first look starts the session, then the clock moves on.
  const started = new WeakSet<object>()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const look = async ($: any, w: ReturnType<typeof world>) => {
    if (!started.has(w)) {
      started.add(w)
      await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    }
    await w.clock.advance(500)
  }
  const ack = (name: string) => `/inbox/${TARGET}/${name}.ack`

  test('a signed file is submitted as the person’s own words and acked', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await settle()
    expect(w.submitted).toEqual([{ text: BODY, asUser: true }])
    expect(w.written[ack(NONCE)]).toBe('ok\n')
  })

  test('is taken once: an acked file is not looked at again, a re-written one is a replay', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await look($, w)
    delete w.inbox[`${TARGET}/${NONCE}.ack`]
    await look($, w)
    await settle()
    expect(w.submitted.length).toBe(1)
    expect(w.written[ack(NONCE)]).toBe('refused: already delivered\n')
  })

  test('a file taken over the peer channel first is refused as a replay', async ($, on) => {
    const w = world(on)
    await receive($, envelope(WIRE))
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await settle()
    expect(w.submitted.length).toBe(1)
    expect(w.written[ack(NONCE)]).toBe('refused: already delivered\n')
  })

  const refused: [string, () => Promise<string>, string, number?][] = [
    ['a bad MAC', async () => WIRE.replace(MAC, '0'.repeat(64)), 'bad signature'],
    ['another key', async () => sign(BODY, { key: '00'.repeat(32) }), 'bad signature'],
    ['another session', async () => sign(BODY, { target: 'cli-other' }), 'addressed to another session'],
    ['a stale message', async () => WIRE, 'stale', TS + 11 * 60 * 1000],
    ['no header', async () => BODY, 'unsigned'],
  ]
  for (const [name, make, reason, now] of refused) {
    test(`refuses ${name}`, async ($, on) => {
      const w = world(on, { now })
      w.inbox[`${TARGET}/${NONCE}.msg`] = await make()
      await look($, w)
      await settle()
      expect(w.submitted).toEqual([])
      expect(w.written[ack(NONCE)]).toBe(`refused: ${reason}\n`)
    })
  }

  test('looks only at its own session’s folder and at .msg files', async ($, on) => {
    const w = world(on)
    w.inbox[`cli-other/${NONCE}.msg`] = WIRE
    w.inbox[`${TARGET}/.${NONCE}.tmp`] = WIRE
    await look($, w)
    await settle()
    expect(w.submitted).toEqual([])
    expect(Object.keys(w.written).filter((k) => k.startsWith('/inbox/'))).toEqual([])
  })

  test('a session with no folder is quiet', async ($, on) => {
    const w = world(on)
    w.sessionId = 'cli-none'
    await look($, w)
    expect(w.submitted).toEqual([])
  })

  test('presence names the capability', () => {
    expect(CAPABILITIES).toEqual(['inbox-v1', 'settings-v1', 'abort-v1'])
  })

  const SETTINGS_NONCE = '223e4567-e89b-12d3-a456-426614174000'
  const put = async (w: ReturnType<typeof world>, settings: Settings, nonce = SETTINGS_NONCE) => {
    w.inbox[`${TARGET}/${nonce}.msg`] = await sign(BODY, { nonce, settings })
  }

  test('v2 signs the settings: the model, then the effort, are set before the text is submitted', async ($, on) => {
    const w = world(on)
    await put(w, { model: 'opus', effort: 'high' })
    await look($, w)
    await settle()
    expect(w.order).toEqual(['model opus', 'effort high', 'submit'])
    expect(w.submitted).toEqual([{ text: BODY, asUser: true }])
    expect(w.written[ack(SETTINGS_NONCE)]).toBe('ok model=opus effort=high\n')
  })

  test('only what was asked for is set', async ($, on) => {
    const w = world(on)
    await put(w, { effort: 'low' })
    await look($, w)
    await settle()
    expect(w.order).toEqual(['effort low', 'submit'])
    expect(w.written[ack(SETTINGS_NONCE)]).toBe('ok effort=low\n')
  })

  test('a command that fails is told in the ack, the other still runs, and the words still go', async ($, on) => {
    const w = world(on)
    w.commandFails.model = 'unknown model'
    await put(w, { model: 'opus', effort: 'max' })
    await look($, w)
    await settle()
    expect(w.order).toEqual(['model opus', 'effort max', 'submit'])
    expect(w.written[ack(SETTINGS_NONCE)]).toMatch(/^ok model=error:\S+ effort=max\n$/)
  })

  test('a full model id is accepted', async ($, on) => {
    const w = world(on)
    await put(w, { model: 'claude-opus-4-5', effort: 'xhigh' })
    await look($, w)
    await settle()
    expect(w.written[ack(SETTINGS_NONCE)]).toBe('ok model=claude-opus-4-5 effort=xhigh\n')
  })

  for (const settings of [{ model: 'gpt-5' }, { model: 'opus;rm' }, { effort: 'extreme' }, { model: 'opus', effort: '--x' }]) {
    test(`refuses ${JSON.stringify(settings)} and sends nothing`, async ($, on) => {
      const w = world(on)
      await put(w, settings)
      await look($, w)
      await settle()
      expect(w.commands).toEqual([])
      expect(w.submitted).toEqual([])
      expect(w.written[ack(SETTINGS_NONCE)]).toMatch(/^refused: invalid (model|effort)/)
    })
  }

  test('settings can’t be forged: changing them after signing is a bad signature', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${SETTINGS_NONCE}.msg`] = (await sign(BODY, { nonce: SETTINGS_NONCE, settings: { model: 'haiku' } })).replace(' haiku ', ' opus ')
    await look($, w)
    await settle()
    expect(w.commands).toEqual([])
    expect(w.written[ack(SETTINGS_NONCE)]).toBe('refused: bad signature\n')
  })

  test('a v1 message sets nothing', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await settle()
    expect(w.commands).toEqual([])
    expect(w.written[ack(NONCE)]).toBe('ok\n')
  })

  test('over the peer channel the settings are not applied (that hook is waited on), the words still arrive', async ($, on) => {
    const w = world(on)
    const result = await receive($, envelope(await sign(BODY, { settings: { model: 'opus' } })))
    await settle()
    expect(result.consumed).toBeDefined()
    expect(w.commands).toEqual([])
    expect(w.submitted).toEqual([{ text: BODY, asUser: true }])
  })

  test('the allowlists', () => {
    expect(invalid({ model: 'sonnet[1m]', effort: 'medium' })).toBeUndefined()
    expect(invalid({ model: 'Opus' })).toBeDefined()
    expect(invalid({ effort: 'ultra' })).toBeDefined()
  })

  test('a v2 header is unknown to a v1-only reader: the old pattern finds nothing', async () => {
    expect(/⟦fjord v1 (\S+) (\S+) (\d+) ([0-9a-f]{64})⟧/.test(await sign(BODY, { settings: { model: 'opus' } }))).toBe(false)
  })
})

describe('taking a delivery back', () => {
  const ABORT_NONCE = '323e4567-e89b-12d3-a456-426614174000'
  // The vector Fjord Computer's Swift tests sign the same abort with (RouterCancelTests.theAbortIsSignedAsThePluginChecksIt).
  const ABORT_MAC = '0dbaf1b1ec9728c6d3c3e507515ae0c1ba74dccda5c17011ccfb04a3f688a66a'
  const signAbort = async (cancels = NONCE, { target = TARGET, nonce = ABORT_NONCE, ts = TS, key = KEY } = {}) =>
    `⟦fjord abort v1 ${target} ${nonce} ${ts} ${cancels} ${await hmac(enc.encode(key), abortMacInput(target, nonce, String(ts), cancels))}⟧\n`
  const started = new WeakSet<object>()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const look = async ($: any, w: ReturnType<typeof world>) => {
    if (!started.has(w)) {
      started.add(w)
      await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    }
    await w.clock.advance(500)
    await settle()
  }
  const ack = (name: string) => `/inbox/${TARGET}/${name}.ack`
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const deliver = async ($: any, w: ReturnType<typeof world>) => {
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const abort = async ($: any, w: ReturnType<typeof world>, text?: string) => {
    w.inbox[`${TARGET}/${ABORT_NONCE}.msg`] = text ?? (await signAbort())
    await look($, w)
    return w.written[ack(ABORT_NONCE)]
  }
  const complete = { durationMs: 1, isAborted: false, reason: 'answer' as const, answer: 'done' }

  test('the wire format matches the vector Fjord Computer signs with', async () => {
    const text = await signAbort()
    expect(text).toBe(`⟦fjord abort v1 ${TARGET} ${ABORT_NONCE} ${TS} ${NONCE} ${ABORT_MAC}⟧\n`)
    expect(parseAbort(text)).toEqual({ target: TARGET, nonce: ABORT_NONCE, ts: String(TS), cancels: NONCE, mac: ABORT_MAC })
    // Not a delivery: nothing would be submitted from it, whatever reads it.
    expect(parse(text)).toBeUndefined()
  })

  test('a running turn the delivery started is aborted', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: BODY, turnId: 't1' })
    expect(await abort($, w)).toBe('ok aborted\n')
    expect(w.aborted).toEqual(['t1'])
  })

  test('a delivery queued behind a running turn ends the moment its turn starts', async ($, on) => {
    const w = world(on)
    await $.turn.start({ text: 'what you typed before', turnId: 't0' })
    await deliver($, w)
    expect(await abort($, w)).toBe('ok before-start\n')
    expect(w.aborted).toEqual([])
    await $.turn.complete({ ...complete, turnId: 't0' })
    await $.turn.start({ text: BODY, turnId: 't1' })
    await settle()
    expect(w.aborted).toEqual(['t1'])
  })

  test('read together with words of the person’s own, its turn is not stopped: neither are they', async ($, on) => {
    const w = world(on)
    await $.turn.start({ text: 'first', turnId: 't0' })
    await deliver($, w)
    expect(await abort($, w)).toBe('ok before-start\n')
    await $.turn.complete({ ...complete, turnId: 't0' })
    await $.turn.start({ text: `something typed\n\n${BODY}`, turnId: 't1' })
    await settle()
    expect(w.aborted).toEqual([])
  })

  test('running together with words of the person’s own, a cancel says so and stops nothing', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: `something typed\n\n${BODY}`, turnId: 't1' })
    expect(await abort($, w)).toBe('ok together\n')
    expect(w.aborted).toEqual([])
  })

  test('two deliveries read together are one turn, taken back with either', async ($, on) => {
    const w = world(on)
    const second = 'And then update the changelog for it'
    const NONCE2 = '523e4567-e89b-12d3-a456-426614174000'
    await deliver($, w)
    w.inbox[`${TARGET}/${NONCE2}.msg`] = await sign(second, { nonce: NONCE2 })
    await look($, w)
    await $.turn.start({ text: `${BODY}\n\n${second}`, turnId: 't1' })
    expect(await abort($, w)).toBe('ok aborted\n')
    expect(w.aborted).toEqual(['t1'])
  })

  test('a short delivery is only its turn when it is the whole turn', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${NONCE}.msg`] = await sign('yes')
    await look($, w)
    // The person's later "yes, run the tests again" is not it.
    await $.turn.start({ text: 'yes, run the tests again', turnId: 't1' })
    expect(await abort($, w)).toBe('ok before-start\n')
    await $.turn.complete({ ...complete, turnId: 't1' })
    expect(w.aborted).toEqual([])
  })

  test('a delivery is forgotten past the window: a later turn of the person’s with its words is never aborted', async ($, on) => {
    const w = world(on)
    await $.turn.start({ text: 'first', turnId: 't0' })
    await deliver($, w)
    expect(await abort($, w)).toBe('ok before-start\n')
    await $.turn.complete({ ...complete, turnId: 't0' })
    await w.clock.advance(11 * 60 * 1000)
    await $.turn.start({ text: BODY, turnId: 't1' })
    await settle()
    expect(w.aborted).toEqual([])
  })

  test('a delivery a hook dropped started nothing, and is forgotten', async ($, on) => {
    const w = world(on)
    w.dropSubmit = true
    await deliver($, w)
    await settle()
    // The person then types the same words: theirs, not Fjord Computer's.
    await $.turn.start({ text: BODY, turnId: 't1' })
    expect(await abort($, w)).toBe('ok unknown\n')
    expect(w.aborted).toEqual([])
  })

  test('cancelled while its turn is starting, it ends as it starts', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    let go = () => {}
    w.holdStart = new Promise((resolve) => {
      go = resolve
    })
    const starting = $.turn.start({ text: BODY, turnId: 't1' })
    await settle()
    w.abortFails = true
    expect(await abort($, w)).toBe('ok before-start\n')
    w.abortFails = false
    go()
    await starting
    expect(w.aborted).toEqual(['t1'])
  })

  test('a turn that is over is too late, and nothing is aborted', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: BODY, turnId: 't1' })
    await $.turn.complete({ ...complete, turnId: 't1' })
    expect(await abort($, w)).toBe('ok too-late\n')
    expect(w.aborted).toEqual([])
  })

  test('another turn starting is not mistaken for it, nor is a subagent ending', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: 'something else entirely', turnId: 't1' })
    await $.turn.complete({ ...complete, turnId: 't1', agentId: 'a1' })
    // Still waiting for its own turn: taken back before it starts.
    expect(await abort($, w)).toBe('ok before-start\n')
  })

  test('a delivery not seen yet is refused when it comes', async ($, on) => {
    const w = world(on)
    expect(await abort($, w)).toBe('ok before-start\n')
    await deliver($, w)
    expect(w.submitted).toEqual([])
    expect(w.written[ack(NONCE)]).toBe('refused: already delivered\n')
  })

  test('one an earlier copy submitted (a reload since) can’t be told', async ($, on) => {
    const w = world(on, { store: { [`nonce.${NONCE}`]: TS } })
    expect(await abort($, w)).toBe('ok unknown\n')
  })

  test('a turn that won’t abort is too late', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: BODY, turnId: 't1' })
    w.abortFails = true
    expect(await abort($, w)).toBe('ok too-late\n')
  })

  test('an abort is taken once', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: BODY, turnId: 't1' })
    await abort($, w)
    delete w.inbox[`${TARGET}/${ABORT_NONCE}.ack`]
    expect(await abort($, w)).toBe('refused: already delivered\n')
    expect(w.aborted).toEqual(['t1'])
  })

  const refused: [string, () => Promise<string>, string, number?][] = [
    ['a bad MAC', async () => (await signAbort()).replace(/[0-9a-f]{64}⟧/, `${'0'.repeat(64)}⟧`), 'bad signature'],
    ['another key', async () => signAbort(NONCE, { key: '00'.repeat(32) }), 'bad signature'],
    ['another delivery named after signing', async () => (await signAbort()).replace(` ${NONCE} `, ' 00000000-0000-0000-0000-000000000000 '), 'bad signature'],
    ['another session', async () => signAbort(NONCE, { target: 'cli-other' }), 'addressed to another session'],
    ['a stale abort', async () => signAbort(), 'stale', TS + 11 * 60 * 1000],
  ]
  for (const [name, make, reason, now] of refused) {
    test(`refuses ${name}`, async ($, on) => {
      const w = world(on, { now })
      if (now === undefined) {
        await deliver($, w)
        await $.turn.start({ text: BODY, turnId: 't1' })
      }
      expect(await abort($, w, await make())).toBe(`refused: ${reason}\n`)
      expect(w.aborted).toEqual([])
    })
  }

  test('over the peer channel an abort is nothing: it passes on as the peer message it is', async ($, on) => {
    const w = world(on)
    await deliver($, w)
    await $.turn.start({ text: BODY, turnId: 't1' })
    const text = envelope(await signAbort())
    const result = await receive($, text)
    expect(result.consumed).toBeUndefined()
    expect(w.aborted).toEqual([])
  })

  test('a delivery over the peer channel can be taken back too', async ($, on) => {
    const w = world(on)
    await receive($, envelope(WIRE))
    await $.turn.start({ text: BODY, turnId: 't1' })
    expect(await abort($, w)).toBe('ok aborted\n')
  })
})

describe('taking back a turn that runs tools', () => {
  const ABORT_NONCE = '423e4567-e89b-12d3-a456-426614174000'
  const started = new WeakSet<object>()
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const look = async ($: any, w: ReturnType<typeof world>) => {
    if (!started.has(w)) {
      started.add(w)
      await $.session.start({ cwd: '/code/app', surface: null, isInteractive: false })
    }
    await w.clock.advance(500)
    await settle()
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const running = async ($: any, w: ReturnType<typeof world>, text = BODY) => {
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await $.turn.start({ text, turnId: 't1' })
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const abort = async ($: any, w: ReturnType<typeof world>) => {
    const mac = await hmac(enc.encode(KEY), abortMacInput(TARGET, ABORT_NONCE, String(TS), NONCE))
    w.inbox[`${TARGET}/${ABORT_NONCE}.msg`] = `⟦fjord abort v1 ${TARGET} ${ABORT_NONCE} ${TS} ${NONCE} ${mac}⟧\n`
    await look($, w)
    return w.written[`/inbox/${TARGET}/${ABORT_NONCE}.ack`]
  }
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const call = ($: any, id: string): Promise<any> => $.tool.call({ tool: 'Bash', command: 'sleep 90', tool_use_id: id })
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const notify = ($: any, text: string): Promise<any> => $.prompt.submit({ text, origin: { kind: 'task-notification' } })

  test('a tool it is running is cut short before the turn is aborted', async ($, on) => {
    const w = world(on)
    await running($, w)
    const pending = call($, 'toolu_1')
    await settle()
    expect(w.ran).toEqual(['toolu_1'])
    expect(await abort($, w)).toBe('ok aborted\n')
    expect(await pending).toEqual({ deny: 'Stopped: the person cancelled this message from Fjord Computer.' })
    expect(w.aborted).toEqual(['t1'])
  })

  test('a notification from one of its tools afterwards is dropped; others pass', async ($, on) => {
    const w = world(on)
    await running($, w)
    void call($, 'toolu_1')
    await settle()
    await abort($, w)
    const dropped = await notify($, '<task-notification><tool-use-id>toolu_1</tool-use-id><status>completed</status></task-notification>')
    expect(dropped.drop).toBeDefined()
    const other = await notify($, '<task-notification><tool-use-id>toolu_9</tool-use-id></task-notification>')
    expect(other.drop).toBeUndefined()
  })

  test('an abort that fails cuts nothing, and mutes nothing', async ($, on) => {
    const w = world(on)
    await running($, w)
    const pending = call($, 'toolu_1')
    await settle()
    w.abortFails = true
    expect(await abort($, w)).toBe('ok too-late\n')
    w.finish.toolu_1()
    expect((await pending).result).toBe('finished')
    expect((await notify($, '<task-notification><tool-use-id>toolu_1</tool-use-id></task-notification>')).drop).toBeUndefined()
  })

  test('a background agent of an earlier turn is left be; one this turn spawned is cut with it', async ($, on) => {
    const w = world(on)
    on('agent.spawn', () => ({ model: 'haiku', agentId: 'a-new' }))
    await running($, w)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    await ($ as any).agent.spawn({ prompt: 'look around' })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const old = ($ as any).tool.call({ tool: 'Bash', command: 'make', tool_use_id: 'toolu_old', agentId: 'a-old' })
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const mine = ($ as any).tool.call({ tool: 'Bash', command: 'make', tool_use_id: 'toolu_mine', agentId: 'a-new' })
    await settle()
    expect(await abort($, w)).toBe('ok aborted\n')
    expect((await mine).deny).toBeDefined()
    w.finish.toolu_old()
    expect((await old).result).toBe('finished')
  })

  test('a notification of several tasks is dropped only when all are the cancelled turn’s', async ($, on) => {
    const w = world(on)
    await running($, w)
    void call($, 'toolu_1')
    await settle()
    await abort($, w)
    const both = '<task-notification><tool-use-id>toolu_1</tool-use-id></task-notification>\n<task-notification><tool-use-id>toolu_9</tool-use-id></task-notification>'
    expect((await notify($, both)).drop).toBeUndefined()
  })

  test('a tool that finishes is answered as it finished', async ($, on) => {
    const w = world(on)
    await running($, w)
    const pending = call($, 'toolu_1')
    await settle()
    w.finish.toolu_1()
    expect((await pending).result).toBe('finished')
  })

  test('the tools of a turn no delivery started pass straight through, and a cancel leaves them be', async ($, on) => {
    const w = world(on)
    w.inbox[`${TARGET}/${NONCE}.msg`] = WIRE
    await look($, w)
    await $.turn.start({ text: 'what you typed yourself', turnId: 't0' })
    const pending = call($, 'toolu_1')
    await settle()
    expect(await abort($, w)).toBe('ok before-start\n')
    w.finish.toolu_1()
    expect((await pending).result).toBe('finished')
    expect(w.aborted).toEqual([])
  })
})
