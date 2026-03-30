require 'digest'
require 'base64'
require 'securerandom'

class McpOauthController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false
  skip_before_action :require_login, raise: false

  before_action :set_cors_headers

  # GET /.well-known/oauth-authorization-server
  def authorization_server_metadata
    base = mcp_base_url
    render json: {
      issuer:                                 base + '/',
      authorization_endpoint:                 base + '/mcp/oauth/authorize',
      token_endpoint:                         base + '/mcp/oauth/token',
      registration_endpoint:                  base + '/mcp/oauth/register',
      response_types_supported:               ['code'],
      grant_types_supported:                  ['authorization_code', 'refresh_token'],
      code_challenge_methods_supported:       ['S256'],
      token_endpoint_auth_methods_supported:  ['none', 'client_secret_post'],
      scopes_supported:                       ['mcp:tools']
    }
  end

  # GET /.well-known/oauth-protected-resource  (and /.well-known/oauth-protected-resource/mcp)
  def protected_resource_metadata
    base = mcp_base_url
    render json: {
      resource:             base + '/mcp',
      authorization_servers: [base + '/'],
      scopes_supported:     ['mcp:tools']
    }
  end

  # POST /mcp/oauth/register  – Dynamic Client Registration (RFC 7591)
  def register
    body = parse_json_body
    return render_oauth_error(400, 'invalid_request', 'Request body required') unless body

    redirect_uris = body['redirect_uris']
    return render_oauth_error(400, 'invalid_redirect_uri', 'redirect_uris required') if redirect_uris.blank?

    # Enforce admin-configured trusted URI whitelist (if any entries are configured)
    allowed = trusted_redirect_uris
    if allowed.any?
      blocked = redirect_uris.reject { |uri| allowed.include?(uri) }
      unless blocked.empty?
        return render_oauth_error(400, 'invalid_redirect_uri',
          "redirect_uri not in admin-allowed list: #{blocked.first}")
      end
    end

    client = McpOauthClient.create!(
      client_id:                   SecureRandom.uuid,
      client_name:                 body['client_name'],
      redirect_uris:               redirect_uris,
      grant_types:                 body['grant_types'] || ['authorization_code'],
      response_types:              body['response_types'] || ['code'],
      token_endpoint_auth_method:  body['token_endpoint_auth_method'] || 'none',
      client_id_issued_at:         Time.current.to_i
    )

    render json: client.to_registration_response, status: :created
  end

  # GET /mcp/oauth/authorize
  def authorize
    client_id              = params[:client_id]
    redirect_uri           = params[:redirect_uri]
    response_type          = params[:response_type]
    code_challenge         = params[:code_challenge]
    code_challenge_method  = params[:code_challenge_method] || 'S256'
    state                  = params[:state]
    scope                  = params[:scope] || 'mcp:tools'

    client = McpOauthClient.find_by(client_id: client_id)
    return render_oauth_error(400, 'invalid_client', 'Unknown client_id') unless client

    return render_oauth_error(400, 'invalid_request', 'response_type must be code') unless response_type == 'code'
    return render_oauth_error(400, 'invalid_request', 'code_challenge required') if code_challenge.blank?
    return render_oauth_error(400, 'invalid_request', 'code_challenge_method must be S256') unless code_challenge_method == 'S256'

    unless client.redirect_uris.include?(redirect_uri)
      return render_oauth_error(400, 'invalid_redirect_uri', 'redirect_uri not registered')
    end

    # Pass OAuth params via URL query string (not session) so they survive
    # Redmine's reset_session call during login (session fixation protection).
    # None of these params are secret — code_challenge is a hash of the verifier.
    redirect_to mcp_consent_path(
      client_id:             client_id,
      redirect_uri:          redirect_uri,
      code_challenge:        code_challenge,
      code_challenge_method: code_challenge_method,
      state:                 state,
      scope:                 scope
    ), allow_other_host: true
  end

  # POST /mcp/oauth/token
  def token
    grant_type = params[:grant_type]

    case grant_type
    when 'authorization_code'
      exchange_authorization_code
    when 'refresh_token'
      exchange_refresh_token
    else
      render_oauth_error(400, 'unsupported_grant_type', "Unknown grant_type: #{grant_type}")
    end
  end

  private

  def exchange_authorization_code
    code          = params[:code]
    code_verifier = params[:code_verifier]
    client_id     = params[:client_id]
    redirect_uri  = params[:redirect_uri]

    return render_oauth_error(400, 'invalid_request', 'code required') if code.blank?
    return render_oauth_error(400, 'invalid_request', 'code_verifier required') if code_verifier.blank?

    auth_code = McpOauthAuthCode.active.find_by(code: code)
    return render_oauth_error(400, 'invalid_grant', 'Invalid or expired authorization code') unless auth_code

    unless auth_code.client_id == client_id
      return render_oauth_error(400, 'invalid_grant', 'client_id mismatch')
    end

    unless auth_code.redirect_uri == redirect_uri
      return render_oauth_error(400, 'invalid_grant', 'redirect_uri mismatch')
    end

    unless verify_pkce(auth_code.code_challenge, code_verifier)
      return render_oauth_error(400, 'invalid_grant', 'PKCE verification failed')
    end

    user = User.find_by(id: auth_code.user_id)
    return render_oauth_error(400, 'invalid_grant', 'User not found') unless user&.active?

    auth_code.destroy

    token = McpOauthToken.create!(
      access_token:      SecureRandom.hex(32),
      refresh_token:     SecureRandom.hex(32),
      client_id:         client_id,
      user_id:           user.id,
      scopes:            auth_code.scopes,
      expires_at:        1.hour.from_now,
      refresh_expires_at: 30.days.from_now
    )

    render json: {
      access_token:  token.access_token,
      token_type:    'Bearer',
      expires_in:    3600,
      refresh_token: token.refresh_token,
      scope:         token.scopes
    }
  end

  def exchange_refresh_token
    refresh_token = params[:refresh_token]
    client_id     = params[:client_id]

    return render_oauth_error(400, 'invalid_request', 'refresh_token required') if refresh_token.blank?

    old_token = McpOauthToken.find_by_refresh_token(refresh_token)
    return render_oauth_error(400, 'invalid_grant', 'Invalid or expired refresh token') unless old_token
    return render_oauth_error(400, 'invalid_grant', 'client_id mismatch') unless old_token.client_id == client_id

    user = User.find_by(id: old_token.user_id)
    return render_oauth_error(400, 'invalid_grant', 'User not found') unless user&.active?

    old_token.destroy

    token = McpOauthToken.create!(
      access_token:       SecureRandom.hex(32),
      refresh_token:      SecureRandom.hex(32),
      client_id:          client_id,
      user_id:            user.id,
      scopes:             old_token.scopes,
      expires_at:         1.hour.from_now,
      refresh_expires_at: 30.days.from_now
    )

    render json: {
      access_token:  token.access_token,
      token_type:    'Bearer',
      expires_in:    3600,
      refresh_token: token.refresh_token,
      scope:         token.scopes
    }
  end

  def verify_pkce(code_challenge, code_verifier)
    expected = Base64.urlsafe_encode64(Digest::SHA256.digest(code_verifier), padding: false)
    ActiveSupport::SecurityUtils.secure_compare(expected, code_challenge)
  end

  def parse_json_body
    body = request.body.read
    JSON.parse(body)
  rescue
    nil
  end

  def trusted_redirect_uris
    raw = Setting.plugin_redmine_mcp&.dig('allowed_redirect_uris').to_s
    raw.lines.map(&:strip).reject(&:blank?)
  end

  def render_oauth_error(status, error, description = nil)
    payload = { error: error }
    payload[:error_description] = description if description
    render json: payload, status: status
  end

  def set_cors_headers
    response.set_header('Access-Control-Allow-Origin', '*')
    response.set_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    response.set_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
    head :ok and return if request.method == 'OPTIONS'
  end

  def mcp_base_url
    "#{request.scheme}://#{request.host_with_port}"
  end
end
