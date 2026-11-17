# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)
require_relative '../../lib/redmine_mcp/legacy_oauth_import'

class McpOauthFlowTest < Redmine::IntegrationTest
  include McpTestSetup
  fixtures :users, :email_addresses, :user_preferences

  def setup
    super
    Setting.rest_api_enabled = '1'
    mcp_settings
    RedmineMcp::Backend.stubs(:available?).returns(true)
    reset_oauth_tables
    @verifier, @challenge = pkce
  end

  def register(extra = {})
    post '/mcp/oauth/register', params: {client_name: 'MCP native test', redirect_uris: [CALLBACK]}.merge(extra).to_json,
         headers: {'Content-Type' => 'application/json'}
    JSON.parse(response.body)
  end

  def mcp_app(scopes: SCOPES, redirect_uri: CALLBACK)
    Doorkeeper::Application.create!(name: 'Native MCP', redirect_uri: redirect_uri, scopes: scopes,
                                    confidential: false, mcp_registration_key: SecureRandom.hex(32))
  end

  def grant(app, **extra)
    Doorkeeper::AccessGrant.create!({application_id: app.id, resource_owner_id: 2,
      redirect_uri: CALLBACK, scopes: app.scopes.to_s, expires_in: 600,
      code_challenge: @challenge, code_challenge_method: 'S256'}.merge(extra))
  end

  def exchange(app, code, endpoint: '/oauth/token', verifier: @verifier)
    post endpoint, params: {grant_type: 'authorization_code', client_id: app.uid,
      redirect_uri: CALLBACK, code: code, code_verifier: verifier}
  end

  def issue(app = mcp_app)
    exchange(app, grant(app).plaintext_token)
    assert_response :success
    [app, JSON.parse(response.body)]
  end

  def authorize_params(app, **extra)
    {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code', state: 'state-check',
     code_challenge: @challenge, code_challenge_method: 'S256'}.merge(extra).compact
  end

  # Any Redmine API call proves which user an access token resolves to.
  def api_user(token)
    get '/users/current.json', headers: {'Authorization' => "Bearer #{token}"}
    response.successful? ? JSON.parse(response.body).dig('user', 'login') : nil
  end

  def test_discovery_points_to_native_server_and_redmineup_endpoint
    get '/.well-known/oauth-authorization-server'
    j = JSON.parse(response.body)
    assert j['authorization_endpoint'].end_with?('/oauth/authorize')
    assert j['token_endpoint'].end_with?('/oauth/token')
    assert j['revocation_endpoint'].end_with?('/oauth/revoke')
    assert j['registration_endpoint'].end_with?('/mcp/oauth/register')
    assert_includes j['token_endpoint_auth_methods_supported'], 'none'
    assert_equal SCOPES.split.sort, j['scopes_supported'].sort
    assert_nil j['client_id_metadata_document_supported']
    get '/.well-known/oauth-protected-resource/mcp'
    j = JSON.parse(response.body)
    assert_equal 'http://www.example.com/mcp', j['resource']
    assert_equal ['http://www.example.com/'], j['authorization_servers']
    assert_equal SCOPES.split.sort, j['scopes_supported'].sort
  end

  def test_discovery_advertises_cimd_only_when_hosts_are_trusted
    mcp_settings('cimd_trusted_hosts' => 'claude.ai')
    get '/.well-known/oauth-authorization-server'
    assert_equal true, JSON.parse(response.body)['client_id_metadata_document_supported']
  end

  def test_protected_resource_metadata_hidden_and_registration_refused_without_backend
    RedmineMcp::Backend.stubs(:available?).returns(false)
    get '/.well-known/oauth-protected-resource/mcp'
    assert_response :not_found
    register
    assert_response :service_unavailable
    assert_equal 'temporarily_unavailable', JSON.parse(response.body)['error']
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_settings_page_shows_status_and_effective_scopes
    log_user('admin', 'admin')
    get '/settings/plugin/redmine_mcp'
    assert_response :success
    assert_select 'textarea[name=?]', 'settings[allowed_redirect_uris]'
    assert_select 'textarea[name=?]', 'settings[cimd_trusted_hosts]'
    assert_select 'textarea[name=?]', 'settings[scopes]'
    assert_includes response.body, SCOPES.split.sort.join(' ')
    assert_includes response.body, 'http://www.example.com/mcp'
  end

  def test_scopes_follow_setting_without_admin_or_unknown_names
    mcp_settings('scopes' => 'view_issues admin no_such_permission mcp_tools')
    assert_equal ['view_issues'], RedmineMcp::Backend.scopes
  end

  def test_dcr_creates_public_application_with_configured_scopes
    j = register(scope: 'admin')
    assert_response :created
    a = Doorkeeper::Application.find_by!(uid: j['client_id'])
    assert_equal SCOPES.split.sort.join(' '), a.scopes.to_s
    assert_equal a.scopes.to_s, j['scope']
    assert_not a.confidential?
    assert RedmineMcp::NativeOauth.mcp?(a)
    log_user('admin', 'admin')
    get '/oauth/applications'
    assert_response :success
    assert_select 'a', text: 'MCP native test'
  end

  def test_dcr_rejects_empty_allowlist_and_untrusted_redirect
    register(redirect_uris: ['https://evil.example/cb'])
    assert_response :bad_request
    assert_equal 'invalid_redirect_uri', JSON.parse(response.body)['error']
    mcp_settings('allowed_redirect_uris' => '')
    register
    assert_response :bad_request
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_dcr_rejects_confidential_and_unsupported_clients
    [{token_endpoint_auth_method: 'client_secret_post'}, {redirect_uris: CALLBACK},
     {grant_types: ['password']}, {grant_types: ['client_credentials']}, {response_types: ['token']},
     {redirect_uris: []}].each do |extra|
      register(extra)
      assert_response :bad_request, extra.inspect
    end
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_dcr_rejects_unsafe_uri_even_if_allowlisted
    %w[http://example.com/cb javascript:alert(1) https://user:pass@example.com/cb https://example.com/cb#fragment].each do |uri|
      mcp_settings('allowed_redirect_uris' => uri)
      register(redirect_uris: [uri])
      assert_response :bad_request, uri
    end
  end

  def test_dcr_wildcard_patterns_for_chatgpt_and_loopback
    mcp_settings('allowed_redirect_uris' => "https://chatgpt.com/connector/oauth/*\nhttp://localhost:*/callback")
    register(client_name: 'ChatGPT', redirect_uris: ['https://chatgpt.com/connector/oauth/AbC_123-x'])
    assert_response :created
    register(client_name: 'Claude Code', redirect_uris: ['http://localhost:51234/callback'])
    assert_response :created
    ['https://chatgpt.com/connector/oauth/a/b', 'https://chatgpt.com/connector/oauth/',
     'https://chatgpt.com/connector/oauth/x?r=https://evil.example', 'https://chatgpt.com.evil.example/connector/oauth/x',
     'http://localhost:1@evil.example/callback', 'http://localhost:51234/callback/../x'].each do |uri|
      register(client_name: 'Other', redirect_uris: [uri])
      assert_response :bad_request, uri
    end
    assert_equal 2, Doorkeeper::Application.count
  end

  def test_native_consent_with_pkce_and_refresh_rotation
    app = mcp_app
    log_user('jsmith', 'jsmith')
    p = authorize_params(app, scope: SCOPES)
    get '/oauth/authorize', params: p
    assert_response :success
    assert_select 'form input[name=code_challenge][value=?]', @challenge
    post '/oauth/authorize', params: p
    assert_response :redirect
    q = query_of(response.location)
    assert_equal 'state-check', q['state']
    exchange(app, q['code'])
    assert_response :success
    j = JSON.parse(response.body)
    assert_equal SCOPES.split.sort, j['scope'].split.sort
    assert_equal 3600, j['expires_in']
    token = Doorkeeper::AccessToken.by_token(j['access_token'])
    assert_not_equal j['access_token'], token.token
    assert_in_delta 30.days.from_now.to_i, token.mcp_refresh_expires_at.to_i, 5
    reset!
    assert_equal 'jsmith', api_user(j['access_token'])
    exchange(app, q['code'])
    assert_response :bad_request
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :success
    refreshed = JSON.parse(response.body)
    assert_not_equal j['refresh_token'], refreshed['refresh_token']
    assert_nil api_user(j['access_token'])
    assert_equal 'jsmith', api_user(refreshed['access_token'])
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
  end

  def test_requested_scopes_are_narrowed_to_the_application
    app = mcp_app
    log_user('jsmith', 'jsmith')
    {'view_issues admin' => 'view_issues', nil => SCOPES, 'mcp:tools' => SCOPES, 'mcp_tools' => SCOPES,
     'admin' => SCOPES}.each do |requested, expected|
      get '/oauth/authorize', params: authorize_params(app, scope: requested)
      assert_response :success, requested.inspect
      assert_select 'input#scope[name=scope]' do |inputs|
        assert_equal expected.split.sort, inputs.first['value'].split.sort, requested.inspect
      end
    end
  end

  def test_native_consent_requires_s256_pkce
    app = mcp_app
    log_user('jsmith', 'jsmith')
    [nil, 'plain'].each do |method|
      get '/oauth/authorize', params: authorize_params(app, code_challenge_method: method)
      assert_response :bad_request
    end
  end

  def test_localhost_loopback_redirect_matches_any_port
    app = mcp_app(redirect_uri: "http://localhost/callback\nhttp://127.0.0.1/callback")
    log_user('jsmith', 'jsmith')
    %w[http://localhost:3118/callback http://127.0.0.1:40123/callback].each do |uri|
      get '/oauth/authorize', params: authorize_params(app, redirect_uri: uri)
      assert_response :success, uri
      assert_select 'input[name=redirect_uri][value=?]', uri
    end
    get '/oauth/authorize', params: authorize_params(app, redirect_uri: 'http://localhost:3118/other')
    assert_select 'input[name=commit][value=Authorize]', 0
  end

  def test_wrong_pkce_and_wrong_client_cannot_exchange
    app = mcp_app
    g = grant(app)
    exchange(app, g.plaintext_token, verifier: 'wrong-verifier')
    assert_response :bad_request
    exchange(mcp_app, g.plaintext_token)
    assert_response :bad_request
  end

  def test_locked_user_and_expired_refresh_rejected
    app, j = issue
    Doorkeeper::AccessToken.by_token(j['access_token']).update_columns(mcp_refresh_expires_at: 1.second.ago)
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
    app, j = issue
    User.find(2).update_columns(status: User::STATUS_LOCKED)
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid, refresh_token: j['refresh_token']}
    assert_response :bad_request
    assert_equal 'invalid_grant', JSON.parse(response.body)['error']
  end

  def test_legacy_urls_and_scope_remain_compatible
    app = mcp_app
    get '/mcp/oauth/authorize', params: {client_id: app.uid, scope: 'mcp:tools', state: 'old-client',
                                         resource: 'http://www.example.com/mcp'}
    assert_response :redirect
    uri = URI.parse(response.location)
    assert_equal '/oauth/authorize', uri.path
    q = query_of(response.location)
    assert_nil q['scope']
    assert_equal 'http://www.example.com/mcp', q['resource']
    exchange(app, grant(app).plaintext_token, endpoint: '/mcp/oauth/token')
    assert_response :success
    j = JSON.parse(response.body)
    post '/mcp/oauth/token', params: {grant_type: 'refresh_token', client_id: app.uid,
      refresh_token: j['refresh_token'], scope: 'mcp:tools'}
    assert_response :success
    assert_equal SCOPES.split.sort, JSON.parse(response.body)['scope'].split.sort
  end

  def test_existing_non_mcp_oauth_application_unchanged
    app = Doorkeeper::Application.create!(name: 'Existing REST client', redirect_uri: CALLBACK, scopes: 'view_issues', confidential: false)
    assert_not RedmineMcp::NativeOauth.mcp?(app)
    log_user('jsmith', 'jsmith')
    get '/oauth/authorize', params: {client_id: app.uid, redirect_uri: CALLBACK, response_type: 'code', scope: 'view_issues'}
    assert_response :success
  end

  def test_administrator_can_revoke_one_user_inside_applications
    app, j = issue
    other = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 3, scopes: SCOPES, expires_in: 3600)
    g = grant(app)
    log_user('admin', 'admin')
    get "/oauth/applications/#{app.id}"
    assert_response :success
    assert_select '#mcp-native-authorizations tbody tr', 2
    delete "/oauth/applications/#{app.id}/mcp_authorizations/2"
    assert_redirected_to "/oauth/applications/#{app.id}"
    assert Doorkeeper::AccessToken.by_token(j['access_token']).revoked?
    assert g.reload.revoked?
    assert_not other.reload.revoked?
  end

  def test_regular_user_cannot_revoke_someone_elses_authorizations
    app, j = issue
    log_user('dlopper', 'foo')
    delete "/oauth/applications/#{app.id}/mcp_authorizations/2"
    assert_response :forbidden
    assert_not Doorkeeper::AccessToken.by_token(j['access_token']).revoked?
  end

  def test_user_can_revoke_own_native_authorization
    app, j = issue
    log_user('jsmith', 'jsmith')
    delete "/oauth/authorized_applications/#{app.id}"
    assert_response :redirect
    reset!
    assert_nil api_user(j['access_token'])
  end

  def test_disabled_rest_api_prevents_new_authorization
    app = mcp_app
    log_user('jsmith', 'jsmith')
    Setting.rest_api_enabled = '0'
    get '/oauth/authorize', params: authorize_params(app)
    assert_response :forbidden
  end

  def test_legacy_import_preserves_client_tokens_pkce_and_expiry
    c = McpOauthClient.create!(client_id: 'legacy-client', client_name: 'Legacy', redirect_uris: [CALLBACK])
    old = McpOauthToken.create!(client_id: c.client_id, user_id: 2, access_token: 'legacy-access',
      refresh_token: 'legacy-refresh', scopes: 'mcp:tools', expires_at: 20.minutes.from_now, refresh_expires_at: 2.days.from_now)
    McpOauthAuthCode.create!(client_id: c.client_id, user_id: 2, code: 'legacy-code', redirect_uri: CALLBACK,
      scopes: 'mcp:tools', code_challenge: @challenge, code_challenge_method: 'S256', expires_at: 10.minutes.from_now)
    RedmineMcp::LegacyOauthImport.run!
    a = Doorkeeper::Application.find_by!(uid: c.client_id)
    token = Doorkeeper::AccessToken.by_token('legacy-access')
    assert_equal 2, token.resource_owner_id
    assert_equal a.id, token.application_id
    assert_in_delta old.expires_at.to_i, token.expires_at.to_i, 1
    assert_in_delta old.refresh_expires_at.to_i, token.mcp_refresh_expires_at.to_i, 1
    assert_not_equal 'legacy-access', token.token
    exchange(a, 'legacy-code', endpoint: '/mcp/oauth/token')
    assert_response :success
  end

  def test_import_collision_fails_atomically
    mcp_app.update!(uid: 'collision')
    McpOauthClient.create!(client_id: 'collision', redirect_uris: [CALLBACK])
    assert_raises(RuntimeError) { RedmineMcp::LegacyOauthImport.run! }
    assert_equal 1, Doorkeeper::Application.count
    assert_equal 0, Doorkeeper::AccessToken.count
  end
end
