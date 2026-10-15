require_dependency File.join(File.dirname(__FILE__), 'lib/redmine_mcp/tools')
require_dependency File.join(File.dirname(__FILE__), 'lib/redmine_mcp/authorization')

Redmine::Plugin.register :redmine_mcp do
  name        'Redmine MCP Plugin'
  author      'Redmine MCP'
  description 'Exposes Redmine as a Model Context Protocol (MCP) server with OAuth 2.1 for Claude AI'
  version     '1.1.0'

  requires_redmine version_or_higher: '7.0'

  settings default: {
    'allowed_redirect_uris' => "https://claude.ai/api/mcp/auth_callback\n"
  }, partial: 'settings/mcp_settings'

  permission :mcp_tools, {}, require: :loggedin
end

require_relative 'lib/redmine_mcp/native_oauth'
