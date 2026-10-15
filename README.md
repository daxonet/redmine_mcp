# Redmine MCP Plugin

A Redmine plugin that exposes Redmine as a [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) server with OAuth 2.1 authentication, enabling Claude AI and other MCP clients to access Redmine data.

## Features

- **MCP Server** — Streamable HTTP transport at `/mcp` with 10 tools
- **OAuth 2.1 + PKCE** — Authorization Code flow with S256 code challenge
- **Dynamic Client Registration** — RFC 7591 compliant at `/mcp/oauth/register`
- **SSO-compatible consent page** — Uses existing Redmine session, no password re-entry
- **Admin panel** — View, filter, and revoke OAuth authorizations at `/admin/mcp/tokens`
- **Trusted URI whitelist** — Admin-controlled redirect URI allowlist

## MCP Tools

| Tool | Description |
|---|---|
| `list_projects` | List visible projects |
| `get_project` | Get project details |
| `list_issues` | List issues with filters |
| `get_issue` | Get issue details |
| `create_issue` | Create a new issue |
| `update_issue` | Update an existing issue |
| `list_users` | List users (admin only) |
| `search` | Full-text search |
| `list_time_entries` | List time entries |
| `create_time_entry` | Log time on an issue |

## Installation

1. Clone this plugin into Redmine's `plugins/` directory:
   ```sh
   git clone https://github.com/your-org/redmine_mcp plugins/redmine_mcp
   ```

2. Run migrations:
   ```sh
   bundle exec rake redmine:plugins:migrate RAILS_ENV=production
   ```

3. Restart Redmine.

## Usage with Claude AI

1. In Claude, add a new MCP connector with URL `https://your-redmine-host/mcp`
2. Claude will initiate the OAuth flow and open your browser
3. Log in to Redmine and click **Authorize**
4. Claude now has access to your Redmine data

## Admin Configuration

Navigate to **Administration → MCP Authorizations** to:
- View all active OAuth tokens
- Filter by user, client name, or status
- Revoke individual tokens or all tokens for a user
- Manage trusted redirect URI whitelist

## Development

### Setup (Dev Container)

Open in VS Code with the Dev Containers extension. The container will:
- Install Redmine 5.1, 6.0, and 6.1
- Symlink this plugin into each version
- Set up test databases

### Run Unit/Functional/Integration Tests

```sh
RAILS_ENV=test bundle exec rake redmine:plugins:test NAME=redmine_mcp
```

### Run E2E Tests

```sh
npx playwright test --reporter list --workers 1
```

### Lint

```sh
npm run lint        # TypeScript
```

## Compatibility

| Redmine | Database |
|---|---|
| 5.1, 6.0, 6.1 | SQLite, MySQL 5.7+, PostgreSQL 14+ |
| 7.0.2 (validated with Ruby 3.3 / Rails 8.1) | MySQL 8.4 |

## License

GPL-2.0

### Redmine 7 authorization and write behavior

OAuth tokens retain the user’s Redmine permissions. Project administration,
versions, categories, wiki, memberships, and time entry writes check the
corresponding permissions before calling their handlers. Issue writes use
Redmine safe attributes and workflow checks, including tracker restrictions.
Issue notes can supply the change reason required by the Daxonet statistics
plugin; callers can also send an explicit `reason` on `update_issue`.

Issue creation/update and attachment association share a database transaction.
Invalid or incomplete attachment results return an error and roll back the issue
and journal changes. Version API `due_date` maps to Redmine’s `effective_date`;
membership principals use Redmine’s `user_id` foreign key.

Standalone regressions (run from the Redmine installation):

```sh
bundle exec ruby plugins/redmine_mcp/test/standalone/tool_authorization_test.rb
bundle exec ruby plugins/redmine_mcp/test/standalone/tool_serialization_test.rb
```
