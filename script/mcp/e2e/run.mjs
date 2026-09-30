// End-to-end check of the MCP server with the official TypeScript SDK clients,
// against a running server with the test fixtures loaded:
//
//   RAILS_ENV=test bin/rails server -p 3917          # fact_factory_api test database loaded by the suite
//   cd script/mcp/e2e && npm install
//   MCP_URL=http://127.0.0.1:3917/mcp BUILDCANADA_API_KEY=bc_live_… node run.mjs
//
// v1 (@modelcontextprotocol/sdk) connects with the 2025-11-25 initialize
// handshake; v2 (@modelcontextprotocol/client) is pinned to the stateless
// 2026-07-28 lifecycle. Both validate structuredContent against outputSchema.
import { Client as ClientV1 } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport as TransportV1 } from "@modelcontextprotocol/sdk/client/streamableHttp.js";
import { Client as ClientV2, StreamableHTTPClientTransport as TransportV2 } from "@modelcontextprotocol/client";
import { exercise } from "./check.mjs";

const url = new URL(process.env.MCP_URL ?? "http://127.0.0.1:3917/mcp");
const key = process.env.BUILDCANADA_API_KEY;
if (!key) throw new Error("Set BUILDCANADA_API_KEY to a key with read:public.");
const requestInit = { headers: { Authorization: `Bearer ${key}` } };

try {
  await new ClientV1({ name: "e2e-anonymous", version: "1" }).connect(new TransportV1(url));
  console.log("FAIL anonymous connect succeeded");
  process.exitCode = 1;
} catch (e) {
  console.log(`PASS anonymous connect refused (${e.constructor.name})`);
}

const v1 = new ClientV1({ name: "e2e-v1", version: "1" });
const t1 = new TransportV1(url, { requestInit });
await v1.connect(t1);
console.log(`INFO v1 negotiated ${t1.protocolVersion}`);
await exercise(v1, "v1 (sdk 1.31.0, initialize)");
await v1.close();

const v2 = new ClientV2({ name: "e2e-v2", version: "1" }, { versionNegotiation: { mode: { pin: "2026-07-28" } } });
await v2.connect(new TransportV2(url, { requestInit }));
console.log(`INFO v2 negotiated ${v2.getNegotiatedProtocolVersion()}`);
await exercise(v2, "v2 (client 2.2.0, 2026-07-28)");
await v2.close();
