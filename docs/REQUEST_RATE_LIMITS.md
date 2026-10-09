# Request frequency limits

All builds use the same server protection. Cloudflare Rate Limiting bindings
protect entry points; authenticated store and room entry requests also use the
verified VK account ID. User-supplied IDs, nicknames and session renewal do not
change the account key. CF-Connecting-IP is supplied by Cloudflare; other proxy
headers are not trusted.

| Route | Scope | Limit |
| --- | --- | --- |
| Client API, excluding payment callback | Edge IP | 6000/minute |
| VK session bootstrap | Edge IP | 120/minute |
| Room creation and joining, combined | Edge IP and verified VK account | 30/minute each |
| Store refresh | Verified VK account | 120/minute |
| Purchase preparation | Verified VK account | 12/minute |
| Room synchronization | Authenticated room member | 150/10 seconds |
| Background heartbeat | Authenticated room member | 30/minute |

Sync normally runs at 10 Hz; the limit provides 50% headroom. Each participant
has independent sync and heartbeat counters. Room counters live in saved room
state, are discarded with expired members, and survive the normal room storage
restore. The existing periodic save can lose up to approximately five seconds of
counter updates on eviction. Leaving a room remains possible after throttling.

The broad IP limit accommodates eight players at 10 Hz behind one router. IP
limits may still affect large shared networks. Edge binding counters are local
to a Cloudflare location and approximate, not a global billing or security quota.
The room object's member counters provide the second layer for gameplay.

Excess client requests return JSON with HTTP 429, Retry-After and retry_after.
The engine waits without counting this as a network failure or immediately
disconnecting. Missing or failed bindings in a deployment with
RATE_LIMIT_ENABLED=true return 503 with Retry-After. Unit fixtures may omit
bindings; production config explicitly enables and declares all five bindings.

VK payment callbacks keep their own signature, idempotency and retry protocol.
They are excluded from client limits to avoid delaying legitimate orders.
No real payment or deployment is performed by these checks.

Validation: npm run test:vk, node --test tests/room-core.test.mjs and Wrangler
deploy --dry-run. A dry run validates config and bundles only; deploy the branch
through the normal pipeline before checking limits in the production VK app.
