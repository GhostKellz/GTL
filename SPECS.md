# Ghost Transport Layer (GTL) — Specifications

> **GTL** is the unified transport layer for all Ghost projects, providing a consistent API across
> multiple protocols (QUIC, HTTP/3, gRPC, WebSockets, SSE, WebTransport, stdio).  
> It ensures reliable, low-latency, and future-proof communication for AI interactions, coding agents,
> and multi-model orchestration.

---

## 🎯 Goals

- **Multiplexed sessions:** Handle multiple conversations/models on a single connection.
- **Uniform RPC schema:** Same API surface across transports (`chat.complete`, `chat.stream`, `session.patch`).
- **Transport independence:** QUIC-first, but fall back to gRPC, WS, or SSE when needed.
- **Hot-swap capability:** Switch transports mid-session without dropping context.
- **Future-proofing:** WebTransport, MASQUE, and other emerging protocols supported later.
- **Security:** Central OIDC/JWT (`GhostToken`) for all clients; providers hidden behind GTL.

---

## 🔑 Core RPC Shapes

1. **Unary**  
   Request → Response (e.g. `chat.complete`).

2. **Server-stream**  
   Request → Stream of events (e.g. `chat.stream`, token streaming).

3. **Bi-directional stream**  
   Client events ↔ Server events (e.g. `session.patch`, real-time diffs).

---

## 📡 Transport Adapters

| Protocol        | Use Case                                   |
|-----------------|--------------------------------------------|
| **QUIC (UDP)**  | Default for low-latency, multiplexed streams |
| **HTTP/3**      | QUIC with enterprise infra (reverse proxies, TLS) |
| **gRPC (H2)**   | Proven ecosystem, rich streaming + tooling |
| **gRPC over QUIC (H3)** | Cutting-edge, high-perf RPC |
| **WebTransport**| QUIC-native browser support (future web clients) |
| **WebSocket**   | Universal fallback, JSON streaming         |
| **SSE**         | Last-resort fallback for locked-down envs  |
| **Stdio/UDS**   | Local editor ↔ daemon (fastest path)       |

---

## 🧩 Message Model

All transports normalize to the same event format:

```json
{ "type": "status", "state": "streaming" }
{ "type": "token", "text": "partial..." }
{ "type": "patch", "op": {"Replace": {"range": {"sl":10,"sc":0,"el":12,"ec":0}, "text":"..." }}, "rev": 42 }
{ "type": "usage", "tokens_in": 1024, "tokens_out": 256, "cost": 0.0031 }
{ "type": "error", "code": "PROVIDER_TIMEOUT", "msg": "Claude did not respond" }
{ "type": "done" }

---

## 🔒 Authentication

All GTL requests must be authenticated. The standard mechanism is a **GhostToken** — a signed JWT issued by GhostAuth.

### Identity Providers
- **Google Sign-In (OIDC)**
- **GitHub OAuth**
- **Microsoft Entra ID / Azure AD**
- **Custom Enterprise SSO (SAML/OAuth2)**
- **Local development mode** (ephemeral dev tokens)

### Token Flow
1. Client performs OAuth/OIDC flow with chosen IdP.
2. GhostAuth exchanges token → issues a **GhostToken (JWT)** with:
   - `sub`: user ID
   - `iss`: `ghostauth.<domain>`
   - `exp`: expiry
   - `aud`: `gtl` (audience)
   - `scopes`: authorized capabilities
3. GTL clients include token in requests:


Authorization: Bearer <ghosttoken>
4. Server validates token signature + claims.  
5. Providers (OpenAI, Claude, Gemini, etc.) are accessed via the GTL backend, never directly by clients.

### Advantages
- Centralized authentication
- No raw API keys in clients
- Supports multi-user/team environments
- Enterprise-ready (RBAC, auditing)

---

## 📦 Session Model

### Session IDs
- Each conversation or stream is associated with a **session ID** (`sid`).
- Sessions are unique per user + model + context.

### Session Lifecycle
- **Start**: Client requests new session with model + options.
- **Stream**: Tokens, patches, usage events flow via GTL.
- **Switch**: Clients may switch model mid-session; GTL handles context replay.
- **Resume**: Clients may rejoin with `sid` after network drop (resume token required).
- **End**: Session explicitly closed or expires after inactivity.

### Multiplexing
- Multiple sessions may run concurrently over one QUIC/gRPC/WebSocket connection.
- Each session is tagged by its `sid` in events.

### Versioning
- Clients declare GTL protocol version (`gtl/1`, `gtl/2`) at connection.
- Breaking changes require explicit version negotiation.

---

## 📡 Events (Transport-agnostic)

Example session stream:

```json
{ "sid": "abc123", "type": "status", "state": "streaming" }
{ "sid": "abc123", "type": "token", "text": "fn greet() {" }
{ "sid": "abc123", "type": "patch", "op": {"Insert": {"range":{"sl":10,"sc":0,"el":10,"ec":0},"text":"console.log('hi')"}} }
{ "sid": "abc123", "type": "usage", "tokens_in": 1024, "tokens_out": 512, "cost": 0.0062 }
{ "sid": "abc123", "type": "done" }

---

## 🛡️ Security Considerations

- **Ephemeral tokens**: Short-lived GhostTokens prevent long-term credential leaks.  
- **Capability scopes**: Tokens carry scopes (e.g. `chat:read`, `chat:write`, `session:admin`) to restrict features.  
- **Audit logging**: Every session start, stop, and provider call logged for compliance.  
- **Rate limiting**: Per-user and per-org limits enforced at GTL entrypoints.  
- **Zero-trust by design**: Raw provider API keys (OpenAI, Anthropic, etc.) are never exposed to clients.  
- **Encryption**: QUIC/HTTP3 always with TLS 1.3; session state persisted with envelope encryption.  

---

## 🛠️ Roadmap

### v0.1 — MVP
- ✅ QUIC native transport (Zig + Rust SDKs)  
- ✅ gRPC over HTTP/2 adapter  
- ✅ SSE fallback for locked-down networks  
- ✅ Session IDs + basic resume support  
- ✅ GhostToken (JWT) authentication  
- ✅ Core RPCs: `chat.complete`, `chat.stream`, `session.patch`  

### v0.2 — Enhanced Connectivity
- 🔄 gRPC over HTTP/3 (QUIC)  
- 🔄 WebSocket transport  
- 🔄 Unix domain socket / stdio for local editor ↔ daemon  
- 🔄 Hot transport swapping (QUIC ⇆ WS ⇆ SSE)  

### v0.3 — Browser & Enterprise
- 🌐 WebTransport adapter (native QUIC in browsers)  
- 🛡️ RBAC and org/team scoping for GhostTokens  
- 📊 Health endpoints + Prometheus metrics  
- 🧩 SDKs in Rust, Zig, and TypeScript  

### v1.0 — Production Ready
- 🚀 Multi-region deployment patterns  
- 🧵 Multiplexed sessions with full resume & replay  
- 🔐 Pluggable auth backends (Okta, Keycloak, Auth0)  
- 📦 GTL SDK stable APIs + semantic versioning  
- 🧠 Session caching + federation across Ghost projects  

---

## 🎯 MVP Definition (v0.1)

A GTL MVP is “done” when:
1. Clients can open a QUIC connection and start a session.  
2. Messages (`status`, `token`, `patch`, `usage`, `done`) flow over QUIC and SSE fallback.  
3. GhostToken auth validated per request/connection.  
4. A session can be resumed within 30s of disconnect using `sid`.  
5. Zeke and Grim can both consume streams without special adapters.  

---

## 📈 Success Criteria

- **Performance**:  
  - Sub-50ms average token latency over QUIC  
  - Multiplex at least 10 concurrent sessions per connection  

- **Reliability**:  
  - > 95% uptime across transports  
  - Session resumption within 5s after reconnect  

- **Security**:  
  - 100% of client requests authenticated with GhostToken  
  - No provider keys visible to clients  

- **Adoption**:  
  - Integrated into Zeke CLI + Grim editor  
  - Ghostflow agents orchestrated via GTL streams  
  - SDKs published for Zig and Rust  

---

