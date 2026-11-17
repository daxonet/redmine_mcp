require_relative 'lib/redmine_mcp/backend'
require_relative 'lib/redmine_mcp/redirect_policy'
require_relative 'lib/redmine_mcp/client_metadata_document'
require_relative 'lib/redmine_mcp/dynamic_client_registration'

Redmine::Plugin.register :redmine_mcp do
  name        'Redmine MCP Plugin'
  author      'Redmine MCP'
  description 'Zero-configuration OAuth (dynamic registration and client metadata documents) for the RedmineUP Agent MCP server'
  version     '2.0.0'

  requires_redmine version_or_higher: '7.0'

  settings default: {
    'allowed_redirect_uris' => <<~URIS,
      https://claude.ai/api/mcp/auth_callback
      http://localhost/callback
      http://localhost:*/callback
      http://127.0.0.1/callback
      http://127.0.0.1:*/callback
      https://chatgpt.com/connector_platform_oauth_redirect
      https://chatgpt.com/connector/oauth/*
      http://127.0.0.1:33418
      http://127.0.0.1:33418/
      https://vscode.dev/redirect
    URIS
    'cimd_trusted_hosts' => "claude.ai\nchatgpt.com\n",
    'scopes' => ''
  }, partial: 'settings/mcp_settings'

  # Retired 1.x scope. Kept registered so leftover 1.x applications remain
  # valid Doorkeeper records until an administrator deletes them.
  permission :mcp_tools, {}, require: :loggedin
end

require_relative 'lib/redmine_mcp/native_oauth'
