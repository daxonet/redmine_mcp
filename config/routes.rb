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
  post '/mcp/oauth/token',     to: 'doorkeeper/tokens#create'

  # Consent / login page
  get  '/mcp/consent', to: 'mcp_oauth#authorize'

  # MCP protocol endpoint (Streamable HTTP)
  match '/mcp', to: 'mcp#handle', via: %i[get post delete options]

  delete '/oauth/applications/:application_id/mcp_authorizations/:user_id', to: 'mcp_application_authorizations#destroy', as: :mcp_application_authorization

  # Compatibility bookmark: native Applications owns all authorizations.
  get '/admin/mcp/tokens', to: 'mcp_admin#index', as: :mcp_admin_tokens
end
