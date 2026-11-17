# Redmine MCP 2.0 — zero-configuration sign-in for RedmineUP Agent

Requires Redmine 7.0+ and **RedmineUP Agent** (`redmineup_agent`) with its MCP server enabled.

Since 2.0 this plugin no longer serves MCP tools. The `/mcp` endpoint and all tools come from RedmineUP Agent, which also exposes the RedmineUP plugins (Agile, Helpdesk, CRM, Invoices, …). This plugin adds what RedmineUP Agent leaves to the administrator: clients connect by URL alone, without anyone creating an OAuth application and handing out a client ID and secret.

| Client | How it signs in | Administrator work |
|---|---|---|
| claude.ai, Claude Desktop, mobile | Client ID Metadata Document (falls back to DCR) | none |
| Claude Code | Client ID Metadata Document, loopback redirect on any port | none |
| ChatGPT | Client ID Metadata Document or DCR | none |
| VS Code / GitHub Copilot | Dynamic Client Registration (DCR) | none |
| Microsoft Copilot, other clients that need a secret | — | create an application manually in **Administration → Applications** |

## What the plugin provides

- `/.well-known/oauth-authorization-server` and `/.well-known/oauth-protected-resource[/mcp]`, pointing clients to Redmine's native OAuth server (`/oauth/authorize`, `/oauth/token`, `/oauth/revoke`) and advertising the MCP scopes. These routes take precedence over RedmineUP Agent's own discovery documents.
- **Dynamic Client Registration** at `/mcp/oauth/register` for public clients (`token_endpoint_auth_method: none`). Callback URLs must match the trusted list. Identical registrations reuse one application.
- **Client ID Metadata Documents**: a client whose `client_id` is an https URL on a trusted host (default `claude.ai`, `chatgpt.com`) is fetched once per hour and materialised as a public application with that URL as its client ID.
- Policies for these applications only: mandatory S256 PKCE, one-hour access tokens, rotating 30-day refresh tokens, rejection of locked users. Other OAuth applications keep Redmine's defaults.
- Port-agnostic matching of `http://localhost/...` loopback redirects (Doorkeeper already does this for `127.0.0.1`), as required by Claude Code.
- Per-user revocation on the application page in **Administration → Applications**. Users can revoke their own access in **My account → Authorized applications**.

## Scopes and permissions

Self-registered clients receive the scopes from the plugin setting, or RedmineUP Agent's MCP scope list when the setting is empty. `admin` is never granted. A request for fewer scopes is honoured; a request for scopes the application does not hold is narrowed. A token only limits what a user can do. Users still act within their own Redmine project permissions.

## Configuration

**Administration → Plugins → Redmine MCP → Configure**

- *Trusted callback URLs* — one per line; `*` matches one run of characters without `/ ? # @`. Defaults cover claude.ai, Claude Code (`http://localhost:*/callback`, `http://127.0.0.1:*/callback`), ChatGPT (`https://chatgpt.com/connector/oauth/*`) and VS Code. Plain http is accepted only for loopback hosts. An empty list disables DCR.
- *Trusted client metadata hosts* — hosts whose metadata documents are fetched. An empty list disables CIMD. Redmine needs outbound HTTPS to these hosts.
- *Scopes for self-registered clients* — empty means "follow RedmineUP Agent".

Also required:

1. **Administration → Settings → API**: enable the REST web service.
2. **Administration → Plugins → RedmineUP Agent**: enable *MCP server*. Keep *Allow MCP access with API key* off unless needed.
3. **Administration → Settings → General → Host name and path** must be the public host. RedmineUP Agent builds its `WWW-Authenticate` discovery pointer from this setting.

Users connect with `https://<redmine>/mcp`.

## Upgrade from 1.x

1. Back up the database.
2. Deploy RedmineUP Agent and this version together and run `bundle exec rake redmine:plugins:migrate RAILS_ENV=production`.
3. Migration `RetireBuiltinMcpTools` deletes applications that only hold the retired `mcp_tools` scope, with their grants and tokens. Those tokens cannot use RedmineUP Agent's tools. Every user removes and re-adds the connector once. Other OAuth applications, including Azure SSO, are untouched.
4. Enable RedmineUP Agent's MCP server and check that `/.well-known/oauth-protected-resource/mcp` returns RedmineUP scopes.

The `mcp_tools` permission stays registered so leftover 1.x applications remain valid records. `/mcp/oauth/authorize`, `/mcp/oauth/token` and `/admin/mcp/tokens` remain compatibility URLs. Rollback means restoring the database backup together with the 1.x plugin and disabling RedmineUP Agent's MCP server, because the two plugins claim the same URLs.

## Tests

`RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_mcp`. `test/integration/redmineup_agent_connect_test.rb` runs end to end against RedmineUP Agent when it is installed and is skipped otherwise (public CI). CI covers Redmine 7 with MySQL, PostgreSQL and SQLite.
