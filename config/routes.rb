RedmineApp::Application.routes.draw do
  # OAuth 2.1 Discovery endpoints (at root .well-known)
  get '/.well-known/oauth-authorization-server',
      to: 'mcp_oauth#authorization_server_metadata',
      format: false

  # Path-based protected resource metadata: /.well-known/oauth-protected-resource/mcp
  get '/.well-known/oauth-protected-resource',
      to: 'mcp_oauth#protected_resource_metadata',
      format: false
  get '/.well-known/oauth-protected-resource/*path',
      to: 'mcp_oauth#protected_resource_metadata',
      format: false

  # MCP OAuth sub-routes
  post '/mcp/oauth/register',  to: 'mcp_oauth#register'
  get  '/mcp/oauth/authorize', to: 'mcp_oauth#authorize'
  post '/mcp/oauth/token',     to: 'mcp_oauth#token'

  # Consent / login page
  get  '/mcp/consent', to: 'mcp_consent#new'
  post '/mcp/consent', to: 'mcp_consent#create'

  # MCP protocol endpoint (Streamable HTTP)
  match '/mcp', to: 'mcp#handle', via: %i[get post delete options]

  # Admin: view / revoke OAuth tokens + trusted URLs
  get    '/admin/mcp/tokens',            to: 'mcp_admin#index',           as: :mcp_admin_tokens
  post   '/admin/mcp/settings',          to: 'mcp_admin#update_settings', as: :mcp_admin_settings
  delete '/admin/mcp/tokens/:id',        to: 'mcp_admin#destroy',         as: :mcp_admin_token
  delete '/admin/mcp/tokens',            to: 'mcp_admin#destroy_user',    as: :mcp_admin_revoke_user
end
