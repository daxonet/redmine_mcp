# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)
require_relative '../../lib/redmine_mcp/legacy_oauth_import'

class McpOauthFlowTest < Redmine::IntegrationTest
  fixtures :users
  CALLBACK = 'https://example.com/cb'

  def setup
    super
    Setting.rest_api_enabled = '1'
    Setting.plugin_redmine_mcp = {'allowed_redirect_uris' => CALLBACK}
    McpOauthToken.delete_all
    McpOauthAuthCode.delete_all
    McpOauthClient.delete_all
    Doorkeeper::AccessGrant.delete_all
    Doorkeeper::AccessToken.delete_all
    Doorkeeper::Application.delete_all
    @verifier = SecureRandom.hex(32)
    @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
  end

  def register(extra = {})
    post '/mcp/oauth/register', params: {client_name: 'MCP native test', redirect_uris: [CALLBACK]}.merge(extra).to_json,
         headers: {'Content-Type' => 'application/json'}
    JSON.parse(response.body)
  end

  def native_app
    Doorkeeper::Application.create!(name: 'Native MCP', redirect_uri: CALLBACK, scopes: 'mcp_tools', confidential: false)
  end

  def grant(app, **extra)
    Doorkeeper::AccessGrant.create!({application_id: app.id, resource_owner_id: 1,
      redirect_uri: CALLBACK, scopes: 'mcp_tools', expires_in: 600,
      code_challenge: @challenge, code_challenge_method: 'S256'}.merge(extra))
  end

  def exchange(app, code, endpoint: '/oauth/token', verifier: @verifier)
    post endpoint, params: {grant_type: 'authorization_code', client_id: app.uid,
      redirect_uri: CALLBACK, code: code, code_verifier: verifier}
  end

  def issue(app = native_app)
    g = grant(app)
    exchange(app, g.plaintext_token)
    assert_response :success
    [app, JSON.parse(response.body)]
  end

  def rpc(token)
    post '/mcp', params: {jsonrpc: '2.0', id: 1, method: 'initialize', params: {}}.to_json,
      headers: {'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}"}
  end

  def test_discovery_points_to_native_server
    get '/.well-known/oauth-authorization-server'
    j = JSON.parse(response.body)
    assert j['authorization_endpoint'].end_with?('/oauth/authorize')
    assert j['token_endpoint'].end_with?('/oauth/token')
    assert j['revocation_endpoint'].end_with?('/oauth/revoke')
    assert_equal ['mcp_tools'], j['scopes_supported']
    get '/.well-known/oauth-protected-resource/mcp'
    assert_equal ['mcp_tools'], JSON.parse(response.body)['scopes_supported']
  end

  def test_dcr_creates_native_application_only
    j = register
    assert_response :created
    a = Doorkeeper::Application.find_by!(uid: j['client_id'])
    assert_equal 'mcp_tools', a.scopes.to_s
    assert_not a.confidential?
    assert_equal 0, McpOauthClient.count
    log_user('admin', 'admin')
    get '/oauth/applications'
    assert_response :success
    assert_select 'a', text: 'MCP native test'
  end

  def test_dcr_rejects_empty_allowlist
    Setting.plugin_redmine_mcp = {'allowed_redirect_uris' => ''}
    register
    assert_response :bad_request
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_dcr_rejects_untrusted_redirect
    register(redirect_uris: ['https://evil.example/cb'])
    assert_response :bad_request
  end

  def test_dcr_rejects_invalid_metadata_and_scope_escalation
    [{scope: 'admin'}, {token_endpoint_auth_method: 'client_secret_post'},
     {redirect_uris: CALLBACK}, {grant_types: ['password']}, {redirect_uris: []}].each do |extra|
      register(extra)
      assert_response :bad_request
    end
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_dcr_rejects_unsafe_uri_even_if_allowlisted
    %w[http://example.com/cb javascript:alert(1) https://user:pass@example.com/cb https://example.com/cb#fragment].each do |uri|
      Setting.plugin_redmine_mcp = {'allowed_redirect_uris' => uri}
      register(redirect_uris: [uri])
      assert_response :bad_request
    end
  end

  def test_legacy_authorize_url_normalizes_scope
    get '/mcp/oauth/authorize', params: {client_id: native_app.uid, scope: 'mcp:tools', state: 'old-client'}
    assert_response :redirect
    uri = URI.parse(response.location)
    assert_equal '/oauth/authorize', uri.path
    assert_equal 'mcp_tools', URI.decode_www_form(uri.query).to_h['scope']
  end

  def test_native_consent_with_pkce_and_refresh_rotation
    app = native_app
    log_user('jsmith', 'jsmith')
    p = {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code', scope: 'mcp_tools',
         state: 'state-check', code_challenge: @challenge, code_challenge_method: 'S256'}
    get '/oauth/authorize', params: p
    assert_response :success
    assert_select 'form input[name=code_challenge][value=?]', @challenge
    post '/oauth/authorize', params: p
    assert_response :redirect
    q = URI.decode_www_form(URI.parse(response.location).query).to_h
    assert_equal 'state-check', q['state']
    assert q['code'].present?
    exchange(app, q['code'])
    assert_response :success
    j = JSON.parse(response.body)
    assert j['access_token'].present?
    assert_equal 'mcp_tools', j['scope']
    assert_equal 3600, j['expires_in']
    token = Doorkeeper::AccessToken.by_token(j['access_token'])
    assert_not_equal j['access_token'], token.token
    assert_not_equal j['refresh_token'], token.refresh_token
    assert_in_delta 30.days.from_now.to_i, token.mcp_refresh_expires_at.to_i, 5
    rpc(j['access_token'])
    assert_response :success
    exchange(app, q['code'])
    assert_response :bad_request
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :success
    refreshed = JSON.parse(response.body)
    assert_not_equal j['access_token'], refreshed['access_token']
    assert_not_equal j['refresh_token'], refreshed['refresh_token']
    rpc(j['access_token'])
    assert_response :unauthorized
    rpc(refreshed['access_token'])
    assert_response :success
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
  end

  def test_native_consent_requires_s256_pkce
    app = native_app
    log_user('jsmith', 'jsmith')
    [nil, 'plain'].each do |method|
      get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK,
        response_type: 'code', scope: 'mcp_tools', code_challenge: @challenge, code_challenge_method: method}
      assert_response :bad_request
    end
  end

  def test_wrong_pkce_and_wrong_client_cannot_exchange
    app = native_app
    g = grant(app)
    exchange(app, g.plaintext_token, verifier: 'wrong-verifier')
    assert_response :bad_request
    exchange(native_app, g.plaintext_token)
    assert_response :bad_request
  end

  def test_token_without_mcp_scope_cannot_access_mcp
    app = Doorkeeper::Application.create!(name: 'REST only', redirect_uri: CALLBACK, scopes: 'view_issues', confidential: false)
    token = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 1, scopes: 'view_issues', expires_in: 3600)
    rpc(token.plaintext_token)
    assert_response :unauthorized
  end

  def test_expired_revoked_and_locked_user_tokens_rejected
    app, j = issue
    token = Doorkeeper::AccessToken.by_token(j['access_token'])
    token.update_columns(created_at: 2.hours.ago, expires_in: 1)
    rpc(j['access_token']); assert_response :unauthorized
    token.update_columns(created_at: Time.current, expires_in: 3600, revoked_at: Time.current)
    rpc(j['access_token']); assert_response :unauthorized
    token.update_columns(revoked_at: nil)
    User.find(1).update_columns(status: User::STATUS_LOCKED)
    rpc(j['access_token']); assert_response :unauthorized
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
  end

  def test_expired_refresh_rejected
    app, j = issue
    Doorkeeper::AccessToken.by_token(j['access_token']).update_columns(mcp_refresh_expires_at: 1.second.ago)
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
  end

  def test_native_revocation_and_application_deletion_disable_mcp
    app, j = issue
    post '/oauth/revoke', params: {client_id: app.uid, token: j['access_token']}
    assert_response :success
    rpc(j['access_token']); assert_response :unauthorized
    app, j = issue
    app.destroy!
    rpc(j['access_token']); assert_response :unauthorized
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
  end

  def test_legacy_token_url_is_native
    app = native_app
    g = grant(app)
    exchange(app, g.plaintext_token, endpoint: '/mcp/oauth/token')
    assert_response :success
    assert Doorkeeper::AccessToken.by_token(JSON.parse(response.body)['access_token'])
    assert_equal 0, McpOauthToken.count
  end

  def test_existing_non_mcp_oauth_application_unchanged
    app = Doorkeeper::Application.create!(name: 'Existing REST client', redirect_uri: CALLBACK, scopes: 'view_issues', confidential: false)
    log_user('jsmith', 'jsmith')
    get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code', scope: 'view_issues'}
    assert_response :success
  end

  def test_legacy_import_preserves_client_tokens_pkce_and_expiry
    c = McpOauthClient.create!(client_id: 'legacy-client', client_name: 'Legacy', redirect_uris: [CALLBACK])
    old = McpOauthToken.create!(client_id: c.client_id, user_id: 1, access_token: 'legacy-access',
      refresh_token: 'legacy-refresh', scopes: 'mcp:tools', expires_at: 20.minutes.from_now, refresh_expires_at: 2.days.from_now)
    code = McpOauthAuthCode.create!(client_id: c.client_id, user_id: 1, code: 'legacy-code', redirect_uri: CALLBACK,
      scopes: 'mcp:tools', code_challenge: @challenge, code_challenge_method: 'S256', expires_at: 10.minutes.from_now)
    RedmineMcp::LegacyOauthImport.run!
    a = Doorkeeper::Application.find_by!(uid: c.client_id)
    token = Doorkeeper::AccessToken.by_token('legacy-access')
    assert_equal 1, token.resource_owner_id
    assert_equal a.id, token.application_id
    assert_in_delta old.expires_at.to_i, token.expires_at.to_i, 1
    assert_in_delta old.refresh_expires_at.to_i, token.mcp_refresh_expires_at.to_i, 1
    assert_not_equal 'legacy-access', token.token
    rpc('legacy-access'); assert_response :success
    exchange(a, 'legacy-code', endpoint: '/mcp/oauth/token')
    assert_response :success
    post '/mcp/oauth/token', params: {grant_type: 'refresh_token', client_id: c.client_id, refresh_token: 'legacy-refresh'}
    assert_response :success
    rpc('legacy-access'); assert_response :unauthorized
    # Old plaintext tables never restore access after native revocation.
    Doorkeeper::AccessToken.where(application_id: a.id).update_all(revoked_at: Time.current)
    rpc('legacy-access'); assert_response :unauthorized
  end

  def test_administrator_can_revoke_one_user_inside_applications
    app, j = issue
    other = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 2, scopes: 'mcp_tools', expires_in: 3600)
    g = grant(app)
    log_user('admin', 'admin')
    get "/oauth/applications/#{app.id}"
    assert_response :success
    assert_select '#mcp-native-authorizations tbody tr', 2
    delete "/oauth/applications/#{app.id}/mcp_authorizations/1"
    assert_redirected_to "/oauth/applications/#{app.id}"
    assert Doorkeeper::AccessToken.by_token(j['access_token']).revoked?
    assert g.reload.revoked?
    assert_not other.reload.revoked?
  end

  def test_regular_user_cannot_revoke_someone_elses_authorizations
    app, j = issue
    log_user('jsmith', 'jsmith')
    delete "/oauth/applications/#{app.id}/mcp_authorizations/1"
    assert_response :forbidden
    assert_not Doorkeeper::AccessToken.by_token(j['access_token']).revoked?
  end

  def test_user_can_revoke_own_native_authorization
    app, j = issue
    log_user('admin', 'admin')
    get '/oauth/authorized_applications'
    assert_response :success
    delete "/oauth/authorized_applications/#{app.id}"
    assert_response :redirect
    rpc(j['access_token']); assert_response :unauthorized
  end

  def test_native_mcp_scope_does_not_grant_admin_business_rights
    app = native_app
    t = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 2, scopes: 'mcp_tools', expires_in: 3600)
    before = User.count
    post '/mcp', params: {jsonrpc: '2.0', id: 2, method: 'tools/call',
      params: {name: 'delete_user', arguments: {id: 1}}}.to_json,
      headers: {'Content-Type' => 'application/json', 'Authorization' => "Bearer #{t.plaintext_token}"}
    assert_response :success
    assert_equal true, JSON.parse(response.body).dig('result', 'isError')
    assert_equal before, User.count
  end

  def test_native_authorization_denial_preserves_state_without_grant
    app = native_app
    log_user('jsmith', 'jsmith')
    delete '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code',
      scope: 'mcp_tools', state: 'denied-state', code_challenge: @challenge, code_challenge_method: 'S256'}
    assert_response :redirect
    q = URI.decode_www_form(URI.parse(response.location).query).to_h
    assert_equal 'access_denied', q['error']
    assert_equal 'denied-state', q['state']
    assert_equal 0, Doorkeeper::AccessGrant.count
  end

  def test_wrong_redirect_and_scope_escalation_are_rejected
    app = native_app
    log_user('jsmith', 'jsmith')
    [{redirect_uri: 'https://evil.example/cb'}, {scope: 'mcp_tools admin'}].each do |extra|
      get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code',
        scope: 'mcp_tools', code_challenge: @challenge, code_challenge_method: 'S256'}.merge(extra)
      assert_equal 0, Doorkeeper::AccessGrant.count
      assert_not response.body.include?('name="commit" value="Authorize"')
    end
  end

  def test_disabled_rest_api_prevents_new_authorization
    app = native_app
    log_user('jsmith', 'jsmith')
    Setting.rest_api_enabled = '0'
    get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code',
      scope: 'mcp_tools', code_challenge: @challenge, code_challenge_method: 'S256'}
    assert_response :forbidden
  end

  def test_native_authorization_accepts_default_and_legacy_scope
    app = native_app
    log_user('jsmith', 'jsmith')
    [nil, 'mcp:tools'].each do |scope|
      get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code',
        scope: scope, code_challenge: @challenge, code_challenge_method: 'S256'}
      assert_response :success
      assert_select 'input[name=scope][value=mcp_tools]'
    end
  end

  def test_legacy_explicit_refresh_scope_is_normalized
    app, j = issue
    post '/mcp/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid,
      refresh_token: j['refresh_token'], scope: 'mcp:tools'}
    assert_response :success
    assert_equal 'mcp_tools', JSON.parse(response.body)['scope']
  end

  def test_import_collision_fails_atomically
    native_app.update!(uid: 'collision')
    McpOauthClient.create!(client_id: 'collision', redirect_uris: [CALLBACK])
    assert_raises(RuntimeError) { RedmineMcp::LegacyOauthImport.run! }
    assert_equal 1, Doorkeeper::Application.count
    assert_equal 0, Doorkeeper::AccessToken.count
  end
end
