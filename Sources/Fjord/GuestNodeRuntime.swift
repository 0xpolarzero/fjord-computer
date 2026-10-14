import Foundation

/// The pinned official Node.js release and the guest job that installs it without sending an archive through guest.files.
enum GuestNodeRuntime {
    static let version = "24.21.0"
    static let outputLimit = 64 * 1024
    static let installRootSuffix = ".local/share/fjord/runtime/node-\(version)"

    struct Artifact: Equatable, Sendable {
        var fileName: String
        var sha256: String
        var platform: String
        var url: String { "https://nodejs.org/download/release/v\(version)/\(fileName)" }
    }

    enum Libc: Equatable { case glibc, musl }

    static func artifact(operatingSystem: ComputerKind, architecture: String, libc: Libc = .glibc) -> Artifact? {
        let platform: String
        switch (operatingSystem, architecture.lowercased(), libc) {
        case (.linux, "x86_64", .glibc), (.linux, "amd64", .glibc): platform = "linux-x64"
        case (.linux, "x86_64", .musl), (.linux, "amd64", .musl): platform = "linux-x64-musl"
        case (.linux, "aarch64", .glibc), (.linux, "arm64", .glibc): platform = "linux-arm64"
        case (.macos, "x86_64", _), (.macos, "amd64", _): platform = "darwin-x64"
        case (.macos, "arm64", _), (.macos, "aarch64", _): platform = "darwin-arm64"
        default: return nil
        }
        let checksums: [String: String] = [
            "darwin-arm64": "bed7eea5325e1108f32ce5228ddd6a5f0f08a499ee42aa7442aea583702f6057",
            "darwin-x64": "1462cb3b3046b815cf8ea436d3da450ec1a9f11dac7e5a46b0ada5305d7e8097",
            "linux-arm64": "724282c3b43aec998aa9527380465b45d229e021b58035f5f4f63095eabfe5d5",
            "linux-x64": "6e1db87ef58b8819e5d5402eff1536491b18edd8eb7bee5ef7897876e88dc5ff",
            "linux-x64-musl": "3d63405fc65a0d2d2976c1f0bc2fd27bb0bd07212469e705aac3f03ae5ab4c9c",
        ]
        guard let sha256 = checksums[platform] else { return nil }
        return Artifact(fileName: "node-v\(version)-\(platform).tar.gz", sha256: sha256, platform: platform)
    }

    static func nodePath(home: String) -> String {
        GuestRouterPaths.join(GuestRouterPaths.join(home, installRootSuffix), "bin/node")
    }

    static func provision(client: any GuestClient, computer: GuestReference, account: GuestAccount) async throws {
        let libc: Libc
        if account.operatingSystem == .linux && ["x86_64", "amd64"].contains(account.architecture.lowercased()) {
            let probe = try await client.exec(GuestExecRequest(computer: computer,
                argv: ["/bin/sh", "-c", "test -e /lib/ld-musl-x86_64.so.1 -o -e /lib64/ld-musl-x86_64.so.1"],
                cwd: account.home, timeoutSeconds: 3))
            libc = probe.succeeded ? .musl : .glibc
        } else {
            libc = .glibc
        }
        guard let artifact = artifact(operatingSystem: account.operatingSystem, architecture: account.architecture, libc: libc) else {
            throw GuestClientFailure.unavailable("No pinned Node \(version) runtime is available for \(account.operatingSystem.title) \(account.architecture) \(libc == .musl ? "musl" : "glibc").")
        }
        let root = GuestRouterPaths.join(account.home, installRootSuffix)
        let scriptPath = GuestRouterPaths.join(account.home, ".local/share/fjord/router/provision-runtime.sh")
        _ = try await client.filesWrite(.init(computer: computer, path: scriptPath, data: Data(script.utf8), mode: 0o700))
        let jobId = try await client.execStart(GuestExecStartRequest(computer: computer,
            argv: ["/bin/sh", scriptPath, artifact.url, artifact.sha256, root], cwd: account.home,
            retainOutputBytes: outputLimit))
        var sequence: UInt64 = 0
        var stdout = Data()
        var stderr = Data()
        let deadline = Date().addingTimeInterval(360)
        while Date() < deadline, !Task.isCancelled {
            let result = try await client.execGet(computer: computer, jobId: jobId, sinceSequence: sequence)
            sequence = max(sequence, result.nextSequence)
            if stdout.count < outputLimit { stdout.append(result.stdout.prefix(outputLimit - stdout.count)) }
            if stderr.count < outputLimit { stderr.append(result.stderr.prefix(outputLimit - stderr.count)) }
            switch result.state {
            case .running:
                try await Task.sleep(for: .milliseconds(300))
            case .exited:
                guard result.exitCode == 0 else {
                    let detail = String(decoding: stderr.isEmpty ? stdout : stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    throw GuestClientFailure.unavailable("Node runtime provisioning failed (exit \(result.exitCode ?? -1)): \(detail)")
                }
                return
            case .cancelled:
                throw CancellationError()
            case .lost:
                throw GuestClientFailure.unavailable("Silo lost the Node runtime provisioning job before it finished.")
            }
        }
        throw GuestClientFailure.unavailable("Node runtime provisioning exceeded six minutes. Retry after checking guest network access.")
    }

    static let script = #"""
set -eu
url=$1
expected=$2
install=$3
parent=${install%/*}
mkdir -p "$parent"
if [ -x "$install/bin/node" ] && "$install/bin/node" --version 2>/dev/null | grep -qx "v24.21.0"; then
  printf 'node=%s\n' "$install/bin/node"
  exit 0
fi
stage=$(mktemp -d "$parent/.node-stage.XXXXXX")
backup=""
cleanup() {
  status=$?
  trap - 0
  rm -rf "$stage"
  if [ -n "$backup" ] && [ -e "$backup" ]; then
    if [ -e "$install" ]; then rm -rf "$backup"
    else mv "$backup" "$install" || status=1
    fi
  fi
  exit "$status"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
archive="$stage/node.tar.gz"
curl --fail --location --retry 2 --connect-timeout 15 --max-time 300 --output "$archive" "$url"
if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$archive"); actual=${actual%% *}
elif command -v shasum >/dev/null 2>&1; then
  actual=$(shasum -a 256 "$archive"); actual=${actual%% *}
else
  echo 'No SHA-256 utility is available in the guest.' >&2
  exit 20
fi
[ "$actual" = "$expected" ] || { echo 'Node archive checksum mismatch.' >&2; exit 21; }
tar -xzf "$archive" -C "$stage"
candidate=$(find "$stage" -mindepth 1 -maxdepth 1 -type d -name 'node-v*' -print | sed -n '1p')
[ -n "$candidate" ] && [ -x "$candidate/bin/node" ] || { echo 'Node archive has no executable bin/node.' >&2; exit 22; }
"$candidate/bin/node" --version | grep -qx 'v24.21.0' || { echo 'Node archive version did not match the pin.' >&2; exit 23; }
if [ -e "$install" ]; then backup="$install.old.$$"; mv "$install" "$backup"; fi
mv "$candidate" "$install"
"$install/bin/node" --version | grep -qx 'v24.21.0'
if [ -n "$backup" ]; then rm -rf "$backup"; backup=""; fi
printf 'node=%s\n' "$install/bin/node"
"""#
}
