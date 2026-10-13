# B-27: macOS guest secret proxy

**Verdict: PARTLY.** A macOS VZ guest used the patched MicroSandbox frame engine to substitute a host-only synthetic secret for `allowed.test`, preserve the placeholder for `other.test`, revoke an active TLS relay, and keep a second guest on its own secret. The FileHandle adapter works. The guest's default `dig` query timed out; the tests had to query the engine DNS address explicitly and use `curl --resolve` after that query. B-27 qualifies the adapter and secret behavior, while default DNS query integration remains open.

## Scope and versions

B-27 qualifies the host-proxy route selected by [95 A-15](../95-decisions.md#1-decisions) and described in [50 § macOS host credential-proxy route](../50-access-network-files.md#macos-host-credential-proxy-route-engine-internal-new). The research identified the MicroSandbox frame rings and poll loop as a reuse seam, with a VZ adapter still unverified in [92 §2/§4](../92-macos-proxy-research.md).

- Host: macOS 26.5, build 25F71, arm64.
- Guest template: macOS 26.6.2, build 25G83.
- Silo Dev: 0.11.1; SiloUI source commit `94d81937904af83faf5839e8b28b24e0e1883c8b`.
- MicroSandbox: 0.7.6, commit `09df3d4b9d832adaede1fb9a198cfc660bfab8cd`; Rust 1.94.0.
- Applied Silo patch: `/Users/polarzero/code/projects/microsandbox-workspaces/app/SiloUI/patches/microsandbox-silo-network-0.7.6.patch`, SHA-256 `45b890b9c2a095e4b0dde6da6341e856e06efb11307231547c5778407cff0eeb`.

The source lives in `~/silo-probes/proxy/src`. `prepare-engine.sh` recreates a disposable worktree from the local Cargo checkout and verifies the pinned commit and patch hash. The prototype compiles the public `SmoltcpNetwork` frame backend and lets its configured engine own DNS, TLS interception, secret policy, and live policy updates. There was no fallback to a separate TLS proxy. `TlsProxy` remains an internal engine component; the public network builder and frame backend were sufficient to exercise it.

## Adapter and commands

`host.swift` APFS-clones the Silo Dev disk, auxiliary storage, and hardware model with `cp -c`, creates a unique VZ machine identifier, and configures 4 vCPUs and 8 GiB. It attaches a `VZFileHandleNetworkDeviceAttachment` to one end of an `AF_UNIX/SOCK_DGRAM` socketpair. `gateway.rs` strips the 12-byte virtio-net header, feeds guest Ethernet frames to `SmoltcpNetwork::take_backend()` and returns engine frames through the socketpair. Its admin and SSH ports are slot-specific (`18000 + slot` and `20000 + slot`). The ad-hoc host signature carries the Virtualization and Hypervisor entitlements from `host-entitlements.plist`.

Build commands:

```sh
cd ~/silo-probes/proxy
./src/prepare.sh
./src/prepare-engine.sh
cd src
cargo +1.94.0 build --locked --offline --bin gateway
cd ..
swiftc -O -framework Foundation -framework Virtualization -o tmp/host src/host.swift
codesign --force --sign - --entitlements src/host-entitlements.plist tmp/host
```

Build output:

```text
PATCH_READY commit=09df3d4b9d832adaede1fb9a198cfc660bfab8cd patch_sha=45b890b9c2a095e4b0dde6da6341e856e06efb11307231547c5778407cff0eeb
Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.39s
```

The FileHandle runs used these guest configurations, sequentially:

```sh
TEMPLATE='/Users/polarzero/Library/Application Support/org.silo.dev/macos-templates/25G83-927684672fe5b88d-7f9f89abce396c94'
./tmp/host nat "$TEMPLATE" tmp/clone-A 172.30.0.2 02:53:49:4c:4f:0d 701 tmp/secret-A tmp/engine-ca-A.pem tmp/engine-ca-A-key.pem tmp/upstream-root.pem tmp/engine-ca-export-A.pem
./tmp/host frame "$TEMPLATE" tmp/clone-A 172.30.0.2 02:53:49:4c:4f:0d 701 tmp/secret-A tmp/engine-ca-A.pem tmp/engine-ca-A-key.pem tmp/upstream-root.pem tmp/engine-ca-export-A.pem
./tmp/host frame "$TEMPLATE" tmp/clone-B 172.30.0.6 02:53:49:4c:4f:0e 702 tmp/secret-B tmp/engine-ca-B.pem tmp/engine-ca-B-key.pem tmp/upstream-root.pem tmp/engine-ca-export-B.pem
```

Each secret came from `openssl rand -hex 32`; the secret values were not printed or stored in evidence. The host echo server records only booleans that identify whether a header matched secret A, secret B, or the literal placeholder.

The guests used `/30` subnets: A was `172.30.0.2` through gateway/DNS `172.30.0.1`; B was `172.30.0.6` through gateway/DNS `172.30.0.5`. A loopback DNS server on host port 53535 mapped `allowed.test` and `other.test` to the active gateway. A launch daemon ran `networksetup`, `ifconfig en0`, and `route` during boot; `networksetup` preferences alone did not bring the guest interface up in an earlier B attempt.

The guest CA was copied over SSH and installed with:

```sh
KEY='/Users/polarzero/Library/Application Support/org.silo.dev/macos-templates/25G83-927684672fe5b88d-7f9f89abce396c94/template-access/id_ed25519'
scp -i "$KEY" tmp/engine-ca-export-B.pem silo@192.168.64.29:/tmp/engine-ca-B.pem
ssh -i "$KEY" silo@192.168.64.29 \
  'sudo install -o root -g wheel -m 644 /tmp/engine-ca-B.pem /Users/silo/silo-probe/engine-ca-B.pem && \
   sudo /usr/bin/security add-trusted-cert -d -r trustRoot \
     -k /Library/Keychains/System.keychain \
     /Users/silo/silo-probe/engine-ca-B.pem'
```

The trust command was:

```sh
sudo /usr/bin/security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain \
  /Users/silo/silo-probe/engine-ca-B.pem
```

The B certificate fingerprint in the System keychain was `46724E164457B562A9A3AD366FB279D245452DF34DED1106F63E4DA2AE305721` (`evidence/guest-B-ca-install.txt`).

## Results

The frame gateway started with the expected A interface:

```text
GATEWAY_READY guest=172.30.0.2 gateway=172.30.0.1 dns=172.30.0.1 mac=02:53:49:4c:4f:0d ca=tmp/engine-ca-export-A.pem admin=127.0.0.1:18701
```

The engine's DNS query was necessary to populate the host-to-name binding used by the Silo patch. The guest's default `dig` query using its configured DNS returned `;; connection timed out; no servers could be reached`. These explicit queries succeeded:

```sh
/usr/bin/dig @172.30.0.1 +time=2 +tries=1 +short allowed.test A  # 172.30.0.1
/usr/bin/dig @172.30.0.5 +time=2 +tries=1 +short allowed.test A  # 172.30.0.5
```

The host DNS log recorded `DNS_QUERY allowed.test qtype=1`. HTTPS tests then used `curl --resolve allowed.test:8443:<gateway>` to connect with the same hostname and SNI.

Raw echo-server events, with secret values reduced to match flags:

```text
{"event": "echo", "header_present": true, "path": "/echo", "placeholder_seen": false, "time_ns": 1791914830989824000, "token_is_a": true, "token_is_b": false}
{"event": "echo", "header_present": true, "path": "/echo", "placeholder_seen": true, "time_ns": 1791914831001961000, "token_is_a": false, "token_is_b": false}
{"event": "echo", "header_present": true, "path": "/echo", "placeholder_seen": false, "time_ns": 1791915561494273000, "token_is_a": false, "token_is_b": true}
{"event": "echo", "header_present": true, "path": "/echo", "placeholder_seen": true, "time_ns": 1791915561510882000, "token_is_a": false, "token_is_b": false}
```

For revocation, the A guest opened `/hold`; the echo server recorded `hold_started` with `token_is_a=true`. Sending `REVOKE` to the slot-specific gateway admin port returned `OK removed PROBE_SECRET`. The engine logged `secret policy changed; connection closed`; the guest curl exited with status 52 before release, and the echo server recorded `hold_write write_ok=false` after release:

```text
OK removed PROBE_SECRET
2026-10-13T18:11:36.718733Z DEBUG TLS proxy task ended dst=127.0.0.1:8443 guest_dst=172.30.0.1:8443 error=secret policy changed; connection closed
{"event": "hold_started", "header_present": true, "path": "/hold", "placeholder_seen": false, "time_ns": 1791915079300452000, "token_is_a": true, "token_is_b": false}
{"curl_status": 52, "event": "hold_client_exit", "path": "/report?kind=hold&status=52", "time_ns": 1791915096784595000}
{"event": "hold_write", "path": "/hold", "time_ns": 1791915118585143000, "write_ok": false}
```

The A and B guests ran one at a time. B used a separate MicroSandbox network instance, subnet, engine CA, and synthetic secret. Its allowed-host event matched only secret B, which confirms isolation for this test.

## NAT comparison

Each sample downloaded the same 10 MiB `proof.ovh.net/files/10Mb.dat` object. Medians over three samples:

| Attachment | `time_starttransfer` | `time_total` | Throughput |
| --- | ---: | ---: | ---: |
| Apple VZ NAT | 24.562 ms | 122.440 ms | 85.64 MB/s |
| FileHandle + patched engine, A | 29.814 ms | 244.955 ms | 42.81 MB/s |

The frame path added 5.252 ms median to first byte and doubled the 10 MiB transfer time; throughput fell about 50%. The FileHandle benchmark used `--resolve proof.ovh.net:443:141.95.207.211` because the guest default `dig` query timed out; NAT used its normal resolver. Raw samples are in `evidence/nat-benchmark-A.txt` and `evidence/frame-benchmark-A.txt`. B's own frame median was 34.12 MB/s and is recorded in `evidence/guest-B-frame.log`.

## Spec impact and remaining seam

Record B-27 as **PARTLY**. The recommended `VZFileHandleNetworkDeviceAttachment` to patched frame-engine route in 95 A-15 and 50 Q5/Q6 is viable for host-side secret substitution, non-allowed-host passthrough, live revocation, CA trust, and sequential per-computer isolation. The macOS guest still needs an explicit interface/route bootstrap. Its default `dig` query did not reach the configured engine DNS path in this probe, so production resolver integration remains unqualified; the successful HTTPS tests explicitly queried engine DNS and pinned the connection with `curl --resolve`.

Silo's current VZ NAT attachment remains unchanged. The prototype does not implement Silo's production secret lifecycle, GitHub credential selection, or root-finalization CA delivery. A preliminary A hold attempt found the secret already absent before its intended revoke; cause was not established. The probe then moved the admin control port from a shared fixed port to `18000 + slot` and repeated the revocation test successfully.

Raw evidence is under `~/silo-probes/proxy/evidence`. All probe VMs were stopped, and both APFS clones and all temporary secrets, certificate keys, and the disposable engine worktree were removed after capture. Only probe source and small evidence files remain.
