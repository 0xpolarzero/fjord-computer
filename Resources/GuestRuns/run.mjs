#!/usr/bin/env node
import { spawn } from "node:child_process";
import { promises as fs } from "node:fs";
import path from "node:path";

const [configPath] = process.argv.slice(2);
if (!configPath || !path.isAbsolute(configPath)) fail("The guest run configuration path is invalid.");
const config = JSON.parse(await fs.readFile(configPath, "utf8"));
if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(config.runID)) fail("The run id is invalid.");
if (!path.isAbsolute(config.home) || !path.isAbsolute(config.cwd) || !path.isAbsolute(config.videoPath) || !path.isAbsolute(config.manifestPath)) {
  fail("The guest run paths must be absolute.");
}
await fs.mkdir(path.dirname(config.videoPath), { recursive: true, mode: 0o700 });

let recorder;
let claude;
let taskExitCode;
const startedAt = new Date().toISOString();

try {
  const taskEnvironment = claudeEnvironment();
  await assertNoCompetingAuthentication(config.home, config.cwd);
  if (config.recordProof) recorder = config.platform === "linux" ? await startLinuxRecorder(config) : await startMacRecorder(config);
  claude = spawn(config.claude, claudeArgs(config), {
    cwd: config.cwd,
    env: taskEnvironment,
    stdio: ["ignore", "pipe", "pipe"],
  });
  claude.stdout.on("data", chunk => {
    process.stdout.write(chunk);
  });
  claude.stderr.on("data", chunk => process.stderr.write(chunk));
  claude.on("error", error => {
    process.stderr.write(`Claude could not start: ${safeError(error)}\n`);
    process.exitCode = 127;
  });
  const exitCode = await waitForClaude(claude);
  taskExitCode = exitCode;
  if (exitCode !== 0) {
    process.exitCode = exitCode ?? 1;
  }
} catch (error) {
  process.stderr.write(`Run failed: ${safeError(error)}\n`);
  if (process.exitCode == null) process.exitCode = 1;
} finally {
  if (recorder) {
    try {
      const manifest = await recorder.stop();
      manifest.runID = config.runID;
      manifest.startedAt = startedAt;
      manifest.finishedAt = new Date().toISOString();
      manifest.taskExitCode = taskExitCode ?? process.exitCode ?? 1;
      await atomicJSON(config.manifestPath, manifest);
    } catch (error) {
      process.stderr.write(`Proof recording could not be finalized: ${safeError(error)}\n`);
      await atomicJSON(config.manifestPath, {
        runID: config.runID,
        videoPath: config.videoPath,
        startedAt,
        finishedAt: new Date().toISOString(),
        taskExitCode: taskExitCode ?? process.exitCode ?? 1,
        state: "failed",
        error: safeError(error),
      }).catch(manifestError => {
        process.stderr.write(`Proof failure manifest could not be written: ${safeError(manifestError)}\n`);
      });
      if (process.exitCode == null) process.exitCode = taskExitCode ?? 0;
    }
  }
}

function claudeArgs(value) {
  const args = ["-p", value.prompt, "--output-format", "stream-json", "--verbose",
    "--permission-mode", value.permissionMode];
  if (value.model) args.push("--model", value.model);
  if (value.effort) args.push("--effort", value.effort);
  if (value.allowedTools?.length) args.push("--allowedTools", ...value.allowedTools);
  return args;
}

function claudeEnvironment() {
  const env = { ...process.env };
  // The only supported unattended credential is the Silo placeholder. Never let a higher-precedence local credential win.
  for (const name of ["ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_API_KEY", "ANTHROPIC_AWS_API_KEY", "ANTHROPIC_AWS_BASE_URL",
    "ANTHROPIC_AWS_WORKSPACE_ID", "ANTHROPIC_BASE_URL", "ANTHROPIC_BEDROCK_BASE_URL",
    "ANTHROPIC_BEDROCK_MANTLE_BASE_URL", "ANTHROPIC_BEDROCK_REGION_PREFIX", "ANTHROPIC_BEDROCK_SERVICE_TIER",
    "ANTHROPIC_CUSTOM_HEADERS", "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_FOUNDRY_API_KEY",
    "ANTHROPIC_FOUNDRY_AUTH_TOKEN", "ANTHROPIC_FOUNDRY_BASE_URL", "ANTHROPIC_FOUNDRY_RESOURCE",
    "ANTHROPIC_IDENTITY_TOKEN_FILE", "ANTHROPIC_ORGANIZATION_ID", "ANTHROPIC_PROFILE",
    "ANTHROPIC_VERTEX_BASE_URL", "ANTHROPIC_VERTEX_PROJECT_ID", "ANTHROPIC_WORKSPACE_ID",
    "AWS_PROFILE", "AWS_BEARER_TOKEN_BEDROCK", "AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
    "CLAUDE_CODE_OAUTH_REFRESH_TOKEN", "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST", "CLAUDE_CODE_USE_ANTHROPIC_AWS",
    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_FOUNDRY", "CLAUDE_CODE_USE_MANTLE", "CLAUDE_CODE_USE_VERTEX",
    "CLOUD_ML_REGION", "GOOGLE_APPLICATION_CREDENTIALS"]) {
    delete env[name];
  }
  if (!/^\$MSB_[A-Z0-9_]+$/.test(env.CLAUDE_CODE_OAUTH_TOKEN ?? "")) {
    throw new Error("The guest does not have the Silo CLAUDE_CODE_OAUTH_TOKEN placeholder.");
  }
  return env;
}

async function assertNoCompetingAuthentication(home, cwd) {
  const configDir = process.env.CLAUDE_CONFIG_DIR;
  const userConfig = configDir && path.isAbsolute(configDir) ? configDir : path.join(home, ".claude");
  const candidates = [path.join(userConfig, "settings.json"), path.join(userConfig, "settings.local.json"),
    path.join(cwd, ".claude", "settings.json"), path.join(cwd, ".claude", "settings.local.json"),
    "/etc/claude-code/managed-settings.json", "/Library/Application Support/ClaudeCode/managed-settings.json"];
  const competingAuth = new Set([
    "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_AWS_API_KEY", "ANTHROPIC_AWS_BASE_URL",
    "ANTHROPIC_AWS_WORKSPACE_ID", "ANTHROPIC_BASE_URL", "ANTHROPIC_BEDROCK_BASE_URL",
    "ANTHROPIC_BEDROCK_MANTLE_BASE_URL", "ANTHROPIC_BEDROCK_REGION_PREFIX", "ANTHROPIC_BEDROCK_SERVICE_TIER",
    "ANTHROPIC_CUSTOM_HEADERS", "ANTHROPIC_FEDERATION_RULE_ID", "ANTHROPIC_FOUNDRY_API_KEY",
    "ANTHROPIC_FOUNDRY_AUTH_TOKEN", "ANTHROPIC_FOUNDRY_BASE_URL", "ANTHROPIC_FOUNDRY_RESOURCE",
    "ANTHROPIC_IDENTITY_TOKEN_FILE", "ANTHROPIC_ORGANIZATION_ID", "ANTHROPIC_PROFILE",
    "ANTHROPIC_VERTEX_BASE_URL", "ANTHROPIC_VERTEX_PROJECT_ID", "ANTHROPIC_WORKSPACE_ID",
    "AWS_ACCESS_KEY_ID", "AWS_BEARER_TOKEN_BEDROCK", "AWS_PROFILE", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN",
    "CLAUDE_CODE_OAUTH_REFRESH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
    "CLAUDE_CODE_USE_ANTHROPIC_AWS", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_FOUNDRY",
    "CLAUDE_CODE_USE_MANTLE", "CLAUDE_CODE_USE_VERTEX", "CLOUD_ML_REGION", "GOOGLE_APPLICATION_CREDENTIALS",
  ]);
  for (const file of candidates) {
    try {
      const settings = JSON.parse(await fs.readFile(file, "utf8"));
      if (settings.apiKeyHelper) throw new Error("Remove apiKeyHelper from Claude settings before using the Triage token placeholder.");
      if (settings.forceLoginMethod === "gateway" || settings.forceLoginGatewayUrl) {
        throw new Error("Remove the Claude apps gateway sign-in policy before using the Triage token placeholder.");
      }
      for (const [name, value] of Object.entries(settings.env ?? {})) {
        if (competingAuth.has(name) && value !== "" && value != null) {
          throw new Error(`Remove ${name} from Claude settings before using the Triage token placeholder.`);
        }
      }
    } catch (error) {
      if (error?.code === "ENOENT") continue;
      throw error;
    }
  }
}

async function startLinuxRecorder(value) {
  const display = value.display || process.env.DISPLAY || ":1.0";
  if (!/^:\d+(?:\.\d+)?$/.test(display)) throw new Error("Silo returned an invalid Linux display name.");
  const xauthority = process.env.XAUTHORITY || "/run/silo-desktop/user/Xauthority";
  await fs.access(xauthority);
  const child = spawn("/usr/bin/ffmpeg", ["-hide_banner", "-loglevel", "error", "-y",
    "-f", "x11grab", "-framerate", "5", "-video_size", "1280x720", "-i", display,
    "-vf", "scale=1280:-2", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
    "-movflags", "+frag_keyframe+empty_moov+default_base_moof", value.videoPath], {
      cwd: value.cwd,
      env: { ...process.env, DISPLAY: display, XAUTHORITY: xauthority },
      stdio: ["ignore", "ignore", "pipe"],
    });
  const errors = [];
  child.stderr.on("data", chunk => { if (errors.join("").length < 2048) errors.push(chunk.toString("utf8")); });
  await waitForChildReady(child, value.videoPath, 5_000, "ffmpeg", () => errors.join(""));
  return {
    async stop() {
      if (child.exitCode === null) child.kill("SIGINT");
      const code = await waitForChild(child, 10_000);
      if (![0, 255].includes(code) && child.signalCode !== "SIGINT") {
        throw new Error(`ffmpeg exited with code ${code}: ${errors.join("").slice(0, 400)}`);
      }
      const stat = await fs.stat(value.videoPath);
      if (stat.size === 0) throw new Error("ffmpeg produced an empty recording.");
      const durationText = await execFile("/usr/bin/ffprobe", ["-v", "error", "-show_entries", "format=duration",
        "-of", "default=noprint_wrappers=1:nokey=1", value.videoPath], 8_000);
      return { kind: "ffmpeg-x11grab", videoPath: value.videoPath, bytes: stat.size,
        durationSeconds: Number(durationText.trim()) || null, state: "complete" };
    },
  };
}

async function startMacRecorder(value) {
  const home = process.env.HOME;
  const uid = process.getuid?.();
  if (!home || !uid || !path.isAbsolute(home)) throw new Error("The Aqua recorder account is unavailable.");
  const installRoot = path.join(home, ".local", "share", "fjord", "GuestRuns");
  const install = path.join(installRoot, "GuestRecorder.app");
  const agentDir = path.join(home, "Library", "LaunchAgents");
  const label = `com.fjord.guestruns.${value.runID}`;
  const plistPath = path.join(agentDir, `${label}.plist`);
  const binary = path.join(install, "Contents", "MacOS", "GuestRecorder");
  await fs.mkdir(installRoot, { recursive: true, mode: 0o700 });
  await fs.mkdir(agentDir, { recursive: true, mode: 0o700 });
  await execFile("/usr/bin/ditto", ["-x", "-k", value.recorderArchivePath, installRoot], 30_000);
  const plist = `<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Label</key><string>${label}</string><key>ProgramArguments</key><array><string>${xml(binary)}</string><string>--agent</string><string>${xml(path.dirname(value.videoPath))}</string><string>${xml(value.videoPath)}</string></array><key>RunAtLoad</key><true/><key>KeepAlive</key><false/><key>LimitLoadToSessionType</key><string>Aqua</string></dict></plist>`;
  await atomicText(plistPath, plist);
  await execFile("/bin/launchctl", ["bootstrap", `gui/${uid}`, plistPath], 8_000);
  await execFile("/bin/launchctl", ["kickstart", `gui/${uid}/${label}`], 8_000);
  await waitForFile(path.join(path.dirname(value.videoPath), "recorder-ready.json"), 20_000);
  const readiness = JSON.parse(await fs.readFile(path.join(path.dirname(value.videoPath), "recorder-ready.json"), "utf8"));
  if (readiness.state !== "ready") throw new Error(readiness.error || "ScreenCaptureKit recorder did not become ready.");
  return {
    async stop() {
      await atomicJSON(path.join(path.dirname(value.videoPath), "recorder-command.json"), { action: "stop", runID: value.runID });
      await waitForFile(value.manifestPath, 30_000);
      const manifest = JSON.parse(await fs.readFile(value.manifestPath, "utf8"));
      await execFile("/bin/launchctl", ["bootout", `gui/${uid}/${label}`], 8_000).catch(() => {});
      if (manifest.state !== "complete") throw new Error(manifest.error || "ScreenCaptureKit did not finalize the movie.");
      return manifest;
    },
  };
}

function waitForClaude(child) {
  return new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("close", (code, signal) => resolve(code ?? (signal ? 128 : 1)));
    const stop = () => { if (child.exitCode === null) child.kill("SIGTERM"); };
    process.once("SIGTERM", stop);
    process.once("SIGINT", stop);
  });
}

async function waitForChildReady(child, file, timeout, name, detail) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    if (child.exitCode !== null) throw new Error(`${name} exited before it was ready: ${detail()}`);
    try { if ((await fs.stat(file)).size > 0) return; } catch {}
    await delay(150);
  }
  child.kill("SIGINT");
  throw new Error(`${name} did not create a recording before the deadline: ${detail()}`);
}

async function waitForChild(child, timeout) {
  if (child.exitCode !== null) return child.exitCode;
  return await Promise.race([
    new Promise(resolve => child.once("close", code => resolve(code ?? 1))),
    delay(timeout).then(() => { child.kill("SIGKILL"); throw new Error("Recorder shutdown timed out."); }),
  ]);
}

async function waitForFile(file, timeout) {
  const end = Date.now() + timeout;
  while (Date.now() < end) {
    try { await fs.access(file); return; } catch {}
    await delay(150);
  }
  throw new Error(`Recorder did not publish ${path.basename(file)} before the deadline.`);
}

function execFile(command, args, timeout) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
    let out = "", err = "";
    child.stdout.on("data", part => { if (out.length < 8192) out += part.toString("utf8"); });
    child.stderr.on("data", part => { if (err.length < 8192) err += part.toString("utf8"); });
    const timer = setTimeout(() => { child.kill("SIGKILL"); reject(new Error(`${path.basename(command)} timed out.`)); }, timeout);
    child.once("error", error => { clearTimeout(timer); reject(error); });
    child.once("close", code => {
      clearTimeout(timer);
      if (code === 0) resolve(out);
      else reject(new Error(`${path.basename(command)} exited with code ${code}: ${err.slice(0, 400)}`));
    });
  });
}

async function atomicJSON(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temp = `${file}.${process.pid}.tmp`;
  await fs.writeFile(temp, JSON.stringify(value), { mode: 0o600 });
  await fs.rename(temp, file);
}

async function atomicText(file, value) {
  await fs.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  const temp = `${file}.${process.pid}.tmp`;
  await fs.writeFile(temp, value, { mode: 0o600 });
  await fs.rename(temp, file);
}

function delay(ms) { return new Promise(resolve => setTimeout(resolve, ms)); }
function xml(value) { return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("\"", "&quot;").replaceAll("'", "&apos;"); }
function safeError(error) { return String(error?.message ?? error).replace(/\$MSB_[A-Z0-9_]+/g, "[secret-placeholder]").slice(0, 500); }
function fail(message) { process.stderr.write(`${message}\n`); process.exit(2); }
