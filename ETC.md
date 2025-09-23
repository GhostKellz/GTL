# 👻 Ghost Transport Layer (GTL) — Zig Spec

> **GTL (Zig)** is the multiprotocol transport backbone for the Ghost ecosystem  
> (Zeke, Grim, Ghostflow, Jarvis).  
> Implemented with **Zig + zsync**, it delivers low-latency, secure, and reliable  
> AI communication while staying lightweight, embeddable, and consistent with the  
> rest of the Ghost toolchain.

---

## 🌐 Architecture

Clients (Grim / Zeke / CLI / nvim)
│
GTL Zig SDK (uniform API)
│
┌─────────────────────────────────────┐
│ Transport adapters (runtime-select) │
│ • QUIC (HTTP/3 via msquic/quiche) │
│ • gRPC (HTTP/2 fallback) │
│ • WebSocket (JSON) │
│ • SSE (HTTP/1.1 fallback) │
│ • WebTransport (browser QUIC) │
│ • Local pipe/stdio / UDS │
└─────────────────────────────────────┘
│
Providers (OpenAI, Claude, Gemini, Copilot, Ollama, Local)

yaml
Copy code

---

## ✨ Design Principles

- **QUIC-first**: Multiplexed, low-latency, head-of-line blocking resistance.  
- **Uniform RPC schema**:  
  - `chat.complete` → unary  
  - `chat.stream` → server-stream (tokens, patches, usage)  
  - `session.pipe` → bi-di (optional, for agents/tools)  
- **Hot transport swapping**: Resume sessions across QUIC ⇆ gRPC ⇆ WS ⇆ SSE.  
- **Zero-trust**: GhostToken (OIDC/JWT) is the only client credential; provider keys remain server-side.  
- **Embeddable**: Can run in Grim/Zeke as a linked Zig lib (no daemon required).  

---

## 📦 Default Transport Selection

- **Same host (editor ↔ daemon):** stdio or UDS (fast, no TLS overhead).  
- **LAN/VPN:** gRPC over HTTP/2 (mature streaming).  
- **Public / lossy / mobile:** QUIC (HTTP/3) preferred.  
- **Browsers:** WebTransport (QUIC), fallback gRPC-Web via proxy, fallback WebSocket.  
- **Locked-down infra:** SSE over HTTP/1.1 as a last resort.  

---

## 📡 Message Model (Protocol-Agnostic)

All transports carry the same events:

```jsonc
{ "type": "status", "state": "streaming" }
{ "type": "token", "text": "partial..." }
{ "type": "patch", "op": { "Replace": {
    "range": {"sl":10,"sc":0,"el":12,"ec":0},
    "text":"..." }}, "rev": 42 }
{ "type": "usage", "tokens_in":1024, "tokens_out":256, "cost":0.0031 }
{ "type": "error", "code":"PROVIDER_TIMEOUT", "msg":"..." }
{ "type": "done" }
Encodings:

Protobuf: QUIC, gRPC, WebTransport.

JSON: WS, SSE, local stdio.

🔒 Security
Auth: GhostToken (OIDC/JWT, supports Google/GitHub/Microsoft Entra).

Scopes: chat:*, session:*, tools:*.

Audit: log session metadata (model, usage, duration).

No provider keys in clients — daemon only.

🧵 Zig SDK API (pseudo)
zig
Copy code
pub const Transport = struct {
    pub fn unary(route: []const u8, req: []const u8) ![]u8;
    pub fn serverStream(route: []const u8, req: []const u8,
                        onEvent: fn([]const u8) void) !void;
    pub fn bidi(route: []const u8,
                onEvent: fn([]const u8) void) !StreamHandle;
};

pub fn connect(opts: ConnectOpts) !Transport {
    // try order: stdio → quic → grpc → ws → sse
}
Built on:

zsync for async parallelism.

zqlite for persistent caching + session resume.

C ABI bindings to msquic/quiche for QUIC.

🚀 Roadmap (Zig MVP → Beyond)
MVP (v0.1):

 Define GTLFrame event schema in Zig

 Implement stdio + UDS transport

 Add WebSocket JSON transport

 Basic QUIC via msquic FFI

 Auth validation (GhostToken)

Next (v0.2):

 gRPC(H2) support for infra/tooling

 SSE fallback for proxy-locked networks

 zqlite-based session resume

 Observability hooks (logs/metrics)

Future (v0.3+):

 HTTP/3 QUIC native transport

 WebTransport adapter for browsers

 Hot transport swapping (resume across protocols)

 Multi-region deployment reference

🔑 Why Zig?
Matches Ghostlang/Grim ecosystem (C ABI, embeddable, lean).

zsync + zqlite already proven in Zeke.

Manual memory + comptime = optimized parsers and streaming perf.

Easier to bundle into apps without runtime dependencies.

🏁 Summary
GTL (Zig) is your lean, embeddable, QUIC-first transport layer.
It unifies messy transports into a single client API, while staying consistent
with the Ghost ecosystem’s Zig-first philosophy.
