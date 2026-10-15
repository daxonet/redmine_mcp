# Redmine MCP 1.1.0 — native OAuth

Requires Redmine 7.0+. MCP tools always enforce the signed-in user's Redmine project, issue, workflow and write permissions. An OAuth scope never grants additional business rights.

Applications are managed in **Administration → Applications**. Open an MCP application to inspect authorizations and revoke access for one user; deleting an application revokes every grant. Users can revoke their own grants in **My account → Authorized applications**. There is no separate MCP authorization menu.

Enable Redmine REST API for native OAuth. Configure **Administration → Plugins → Redmine MCP → Configure** with exact trusted callback URLs. An empty allowlist disables dynamic registration. Public MCP clients request `mcp_tools` and must use S256 PKCE. Manually registered Applications must include that scope. Discovery points to `/oauth/authorize`, `/oauth/token`, `/oauth/revoke`; MCP dynamic registration remains `/mcp/oauth/register`. Only MCP-scoped applications receive the PKCE/one-hour access/30-day rolling refresh policies. Other OAuth apps retain Redmine defaults.

## Upgrade from 1.0.x

1. Stop the application and take a complete database + application/files backup.
2. Upgrade Redmine core and migrate it first; deploy this plugin and run `bundle exec rake redmine:plugins:migrate NAME=redmine_mcp RAILS_ENV=production`.
3. The migration imports client IDs, still-valid access/refresh tokens, and unexpired PKCE grants into the native OAuth tables. Secrets are hashed with Redmine's configured strategy, and original expiry bounds are retained. Legacy client secrets were never issued, so migrated clients are public. UID collisions or invalid client records abort the import; fix the source and retry, never bypass the check.
4. Verify Applications, discovery, an existing client's refresh, new authorization, MCP read/write permissions and revocation before reopening traffic.

Existing `/mcp/oauth/authorize` and `/mcp/oauth/token` URLs remain compatibility routes to the native server; the old `mcp:tools` authorization scope is normalized to `mcp_tools` at the compatibility authorization URL. Already-open old consent pages need a new authorization attempt. Legacy tables are retained for audit/backup only: runtime never accepts their credentials, and rerunning the importer can undo revocations and is forbidden. Keep backup/database access restricted since old tables still contain legacy plaintext credentials.

Rollback restores the pre-upgrade database and matching old application together. The migration deliberately has no lossy down conversion from hashed native secrets. Do not run the old plugin against the migrated database.

## Tests

Run `RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_mcp` against a dedicated test database. Standalone checks run separately: `ruby test/standalone/tool_authorization_check.rb` and `ruby test/standalone/tool_serialization_check.rb`. CI covers Redmine 7 with MySQL, PostgreSQL and SQLite. Native OAuth integration tests cover migration, PKCE, token rotation, expiry, user lock, scopes, revocation and compatibility URLs.
