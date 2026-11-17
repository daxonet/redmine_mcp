# frozen_string_literal: true

# MCP discovery and client registration for the RedmineUP Agent MCP server.
# Authorization, consent, token issuance, refresh and revocation are owned by
# Redmine's Doorkeeper server; the /mcp endpoint is owned by RedmineUP Agent.
class McpOauthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false
  skip_before_action :require_login, raise: false

  def authorization_server_metadata
    metadata = {
      issuer: base_url + '/',
      authorization_endpoint: base_url + '/oauth/authorize',
      token_endpoint: base_url + '/oauth/token',
      revocation_endpoint: base_url + '/oauth/revoke',
      registration_endpoint: base_url + '/mcp/oauth/register',
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none', 'client_secret_basic', 'client_secret_post'],
      scopes_supported: RedmineMcp::Backend.scopes
    }
    metadata[:client_id_metadata_document_supported] = true if RedmineMcp::ClientMetadataDocument.enabled?
    render json: metadata
  end

  def protected_resource_metadata
    return head(:not_found) unless RedmineMcp::Backend.available?

    render json: {resource: base_url + '/mcp', authorization_servers: [base_url + '/'],
                  scopes_supported: RedmineMcp::Backend.scopes, bearer_methods_supported: ['header']}
  end

  def register
    unless RedmineMcp::Backend.available? && RedmineMcp::Backend.scopes.any?
      return oauth_error('temporarily_unavailable', 'The Redmine MCP server is not enabled.', :service_unavailable)
    end
    body = JSON.parse(request.body.read)
    return oauth_error('invalid_client_metadata', 'Body must be a JSON object.') unless body.is_a?(Hash)
    uris = body['redirect_uris']
    unless uris.is_a?(Array) && uris.any? && uris.size <= 10 && uris.all? { |uri| RedmineMcp::RedirectPolicy.allowed?(uri) }
      return oauth_error('invalid_redirect_uri', 'Callback URL is not trusted by this Redmine; ask an administrator to add it.')
    end
    unless body.fetch('token_endpoint_auth_method', 'none') == 'none'
      return oauth_error('invalid_client_metadata',
                         'Only public clients with PKCE can register. Ask an administrator for a manually created application.')
    end
    unless (Array(body.fetch('grant_types', ['authorization_code'])) - %w[authorization_code refresh_token]).empty? &&
        Array(body.fetch('response_types', ['code'])) == ['code']
      return oauth_error('invalid_client_metadata', 'Only the authorization code flow is supported.')
    end
    # A requested "scope" is ignored: every client gets the configured MCP scopes.
    app = RedmineMcp::DynamicClientRegistration.register!(
      name: body['client_name'].to_s.strip.presence&.truncate(255) || 'MCP client',
      redirect_uris: uris,
      scopes: RedmineMcp::Backend.scope_string
    )
    render json: {client_id: app.uid, client_id_issued_at: app.created_at.to_i,
                  client_name: app.name, redirect_uris: app.redirect_uri.split,
                  grant_types: %w[authorization_code refresh_token], response_types: ['code'],
                  token_endpoint_auth_method: 'none', scope: app.scopes.to_s}, status: :created
  rescue JSON::ParserError, TypeError, NoMethodError, ActiveRecord::RecordInvalid
    oauth_error('invalid_client_metadata')
  end

  # Compatibility URL for clients configured against 1.x.
  def authorize
    permitted = params.permit(:client_id, :redirect_uri, :response_type, :code_challenge,
                              :code_challenge_method, :state, :scope, :resource).to_h
    permitted['response_type'] ||= 'code'
    permitted.delete('scope') if RedmineMcp::Backend::LEGACY_SCOPES.include?(permitted['scope'])
    redirect_to oauth_authorization_path(permitted)
  end

  private

  def base_url
    request.base_url
  end

  def oauth_error(error, description = nil, status = :bad_request)
    render json: {error: error, error_description: description}.compact, status: status
  end
end
