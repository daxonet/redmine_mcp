import { test, expect } from "@playwright/test";

test.describe("MCP OAuth Discovery", () => {
  test("authorization server metadata", async ({ request }) => {
    const resp = await request.get(
      "http://localhost:3000/.well-known/oauth-authorization-server",
    );
    expect(resp.ok()).toBeTruthy();
    const json = await resp.json();
    expect(json.authorization_endpoint).toContain("/oauth/authorize");
    expect(json.token_endpoint).toContain("/oauth/token");
    expect(json.registration_endpoint).toContain("/mcp/oauth/register");
    expect(json.code_challenge_methods_supported).toContain("S256");
  });

  // Requires RedmineUP Agent with its MCP server enabled.
  test("protected resource metadata", async ({ request }) => {
    const resp = await request.get(
      "http://localhost:3000/.well-known/oauth-protected-resource",
    );
    expect(resp.ok()).toBeTruthy();
    const json = await resp.json();
    expect(json.resource).toContain("/mcp");
    expect(json.scopes_supported).toContain("view_issues");
    expect(json.scopes_supported).not.toContain("admin");
  });

  test("mcp endpoint returns 401 without token", async ({ request }) => {
    const resp = await request.post("http://localhost:3000/mcp", {
      headers: { "Content-Type": "application/json" },
      data: JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: {},
      }),
    });
    expect(resp.status()).toBe(401);
  });
});
