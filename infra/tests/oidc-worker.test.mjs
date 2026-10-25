import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const discoveryPath = "/.well-known/openid-configuration";
const jwksPath = "/openid/v1/jwks";
const documents = {
  [discoveryPath]: {
    issuer: "https://oidc.example.com",
    jwks_uri: "https://oidc.example.com/openid/v1/jwks",
    response_types_supported: ["id_token"],
    subject_types_supported: ["public"],
    id_token_signing_alg_values_supported: ["RS256"],
  },
  [jwksPath]: {
    keys: [{ kty: "RSA", kid: "fixture-kid", alg: "RS256", n: "fixture-n", e: "AQAB" }],
  },
};
const template = await readFile(new URL("../templates/oidc-worker.js.tftpl", import.meta.url), "utf8");
const source = template.replace("${documents}", JSON.stringify(documents));
const { default: worker } = await import(`data:text/javascript;base64,${Buffer.from(source).toString("base64")}`);

function request(path, method = "GET") {
  return worker.fetch(new Request(`https://oidc.example.com${path}`, { method }));
}

for (const path of [discoveryPath, jwksPath]) {
  test(`GET ${path} returns static public metadata`, async () => {
    const response = request(path);
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/json");
    assert.equal(response.headers.get("cache-control"), "public, max-age=300");
    assert.deepEqual(await response.json(), documents[path]);
  });

  test(`HEAD ${path} returns matching headers without body`, async () => {
    const response = request(path, "HEAD");
    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/json");
    assert.equal(await response.text(), "");
  });
}

test("query parameters do not affect discovery", async () => {
  assert.deepEqual(await request(`${discoveryPath}?probe=1`).json(), documents[discoveryPath]);
});

test("unknown paths return 404 without contacting an origin", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => { throw new Error("Worker must not contact an origin"); };
  try {
    for (const path of ["/", "/api/v1/secrets", "/toString", "/__proto__"]) {
      assert.equal(request(path).status, 404);
    }
    assert.equal(await request("/missing", "HEAD").text(), "");
    assert.deepEqual(await request(jwksPath).json(), documents[jwksPath]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

test("non-read methods return 405", () => {
  for (const method of ["POST", "PUT", "PATCH", "DELETE", "OPTIONS"]) {
    const response = request(jwksPath, method);
    assert.equal(response.status, 405);
    assert.equal(response.headers.get("allow"), "GET, HEAD");
  }
});
