# frozen_string_literal: true

# MCP discovery and dynamic registration only. Authorization, consent, token
# issuance, refresh and revocation are owned by Redmine's Doorkeeper server.
class McpOauthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false
  skip_before_action :require_login, raise: false

  def authorization_server_metadata
    render json: {
      issuer: base_url + '/',
      authorization_endpoint: base_url + '/oauth/authorize',
      token_endpoint: base_url + '/oauth/token',
      revocation_endpoint: base_url + '/oauth/revoke',
      registration_endpoint: base_url + '/mcp/oauth/register',
      response_types_supported: ['code'],
      grant_types_supported: ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported: ['S256'],
      token_endpoint_auth_methods_supported: ['none', 'client_secret_basic', 'client_secret_post'],
      scopes_supported: ['mcp_tools']
    }
  end

  def protected_resource_metadata
    render json: {resource: base_url + '/mcp', authorization_servers: [base_url + '/'], scopes_supported: ['mcp_tools']}
  end

  def register
    body = JSON.parse(request.body.read)
    return oauth_error('invalid_client_metadata') unless body.is_a?(Hash)
    uris = body['redirect_uris']
    allowed = Setting.plugin_redmine_mcp.to_h.fetch('allowed_redirect_uris', '').lines.map(&:strip).reject(&:blank?)
    unless uris.is_a?(Array) && uris.any? && uris.size <= 10 &&
        uris.all? { |uri| uri.is_a?(String) && allowed.include?(uri) && valid_uri?(uri) }
      return oauth_error('invalid_redirect_uri')
    end
    unless body.fetch('token_endpoint_auth_method', 'none') == 'none' &&
        (body.fetch('grant_types', ['authorization_code']) - %w[authorization_code refresh_token]).empty? &&
        body.fetch('response_types', ['code']) == ['code'] &&
        %w[mcp_tools mcp:tools].include?(body.fetch('scope', 'mcp_tools'))
      return oauth_error('invalid_client_metadata')
    end
    app = Doorkeeper::Application.create!(
      name: body['client_name'].to_s.presence&.truncate(255) || 'MCP client',
      redirect_uri: uris.uniq.join("\n"), scopes: 'mcp_tools', confidential: false
    )
    render json: {client_id: app.uid, client_id_issued_at: app.created_at.to_i,
                  client_name: app.name, redirect_uris: app.redirect_uri.split,
                  grant_types: %w[authorization_code refresh_token], response_types: ['code'],
                  token_endpoint_auth_method: 'none', scope: 'mcp_tools'}, status: :created
  rescue JSON::ParserError, TypeError, NoMethodError, ActiveRecord::RecordInvalid
    oauth_error('invalid_client_metadata')
  end

  # Compatibility URL for already configured clients, without a second server.
  def authorize
    permitted = params.permit(:client_id, :redirect_uri, :response_type, :code_challenge,
                              :code_challenge_method, :state, :scope).to_h
    permitted['response_type'] ||= 'code'
    permitted['scope'] = 'mcp_tools' if permitted['scope'].blank? || permitted['scope'] == 'mcp:tools'
    redirect_to oauth_authorization_path(permitted)
  end

  private

  def base_url
    request.base_url
  end

  def oauth_error(error)
    render json: {error: error}, status: :bad_request
  end

  def valid_uri?(value)
    uri = URI.parse(value)
    uri.host.present? && uri.userinfo.nil? && uri.fragment.nil? &&
      (uri.scheme == 'https' || (uri.scheme == 'http' && %w[127.0.0.1 localhost ::1].include?(uri.host)))
  rescue URI::InvalidURIError
    false
  end
end
