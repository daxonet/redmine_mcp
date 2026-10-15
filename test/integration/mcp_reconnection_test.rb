# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)
require_relative '../../db/migrate/20261015000005_reset_mcp_clients_for_reconnection'

class McpReconnectionTest < Redmine::IntegrationTest
  fixtures :users
  CALLBACK = 'https://example.com/cb'
  SECOND = 'https://example.com/other'

  def setup
    super
    Setting.rest_api_enabled = '1'
    Setting.plugin_redmine_mcp = {'allowed_redirect_uris' => "#{CALLBACK}\n#{SECOND}"}
    McpOauthToken.delete_all
    McpOauthAuthCode.delete_all
    McpOauthClient.delete_all
    Doorkeeper::AccessGrant.delete_all
    Doorkeeper::AccessToken.delete_all
    Doorkeeper::Application.delete_all
  end

  def register(name: 'Claude', uris: [CALLBACK], scope: 'mcp_tools')
    post '/mcp/oauth/register', params: {client_name: name, redirect_uris: uris, scope: scope}.to_json,
      headers: {'Content-Type' => 'application/json'}
    assert_response :created
    JSON.parse(response.body)
  end

  def test_repeat_registration_reuses_one_public_application
    first = register
    3.times { assert_equal first['client_id'], register['client_id'] }
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_uri_order_duplicates_and_old_scope_do_not_create_duplicates
    first = register(uris: [CALLBACK, SECOND])
    second = register(uris: [SECOND, CALLBACK, SECOND], scope: 'mcp:tools')
    assert_equal first['client_id'], second['client_id']
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_different_metadata_produces_distinct_application
    first = register
    assert_not_equal first['client_id'], register(name: 'Other client')['client_id']
    assert_not_equal first['client_id'], register(uris: [SECOND])['client_id']
    assert_equal 3, Doorkeeper::Application.count
  end

  def test_repeat_registration_preserves_existing_user_tokens
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    token = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 1,
      scopes: 'mcp_tools', expires_in: 3600)
    assert_equal app.uid, register['client_id']
    assert_nil token.reload.revoked_at
    assert_equal 1, Doorkeeper::AccessToken.count
  end

  def test_admin_edited_client_is_not_returned_for_old_registration_metadata
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    app.update!(redirect_uri: SECOND, confidential: true)
    replacement = register
    assert_not_equal app.uid, replacement['client_id']
    assert_nil app.reload.mcp_registration_key
    current = Doorkeeper::Application.find_by!(uid: replacement['client_id'])
    assert_equal CALLBACK, current.redirect_uri
    assert_not current.confidential?
    assert_equal replacement['client_id'], register['client_id']
  end

  def test_database_unique_key_prevents_concurrent_duplicate_insert
    app = Doorkeeper::Application.find_by!(uid: register['client_id'])
    assert_raises(ActiveRecord::RecordNotUnique) do
      Doorkeeper::Application.transaction(requires_new: true) do
        Doorkeeper::Application.create!(name: 'Duplicate', redirect_uri: CALLBACK,
          scopes: 'mcp_tools', confidential: false, mcp_registration_key: app.mcp_registration_key)
      end
    end
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_upgrade_clears_legacy_clients_and_grants_but_preserves_other_oauth_apps
    old = McpOauthClient.create!(client_id: 'old-id', client_name: 'Claude',
      redirect_uris_json: [CALLBACK].to_json, grant_types_json: ['authorization_code'].to_json,
      response_types_json: ['code'].to_json, token_endpoint_auth_method: 'none', client_id_issued_at: Time.current.to_i)
    app = Doorkeeper::Application.create!(uid: old.client_id, name: 'Claude', redirect_uri: CALLBACK,
      scopes: 'mcp_tools', confidential: false)
    token = Doorkeeper::AccessToken.create!(application_id: app.id, resource_owner_id: 1,
      scopes: 'mcp_tools', expires_in: 3600, use_refresh_token: true)
    access = token.plaintext_token
    refresh = token.plaintext_refresh_token
    post '/mcp', params: {jsonrpc: '2.0', id: 1, method: 'initialize', params: {}}.to_json,
      headers: {'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access}"}
    assert_response :success
    McpOauthToken.create!(client_id: old.client_id, user_id: 1, access_token: 'legacy-test-access',
      refresh_token: 'legacy-test-refresh', scopes: 'mcp:tools', expires_at: 1.hour.from_now,
      refresh_expires_at: 1.day.from_now)
    McpOauthAuthCode.create!(client_id: old.client_id, user_id: 1, code: 'legacy-test-code',
      redirect_uri: CALLBACK, scopes: 'mcp:tools', code_challenge: 'a' * 43,
      code_challenge_method: 'S256', expires_at: 10.minutes.from_now)
    grant = Doorkeeper::AccessGrant.create!(application_id: app.id, resource_owner_id: 1,
      redirect_uri: CALLBACK, scopes: 'mcp_tools', expires_in: 600)
    other = Doorkeeper::Application.create!(name: 'Unrelated native OAuth', redirect_uri: SECOND,
      scopes: '', confidential: true)
    other_token = Doorkeeper::AccessToken.create!(application_id: other.id, resource_owner_id: 1,
      scopes: '', expires_in: 3600)
    # Schema is already migrated for the test DB; run the exact migration cleanup.
    migration = ResetMcpClientsForReconnection.new
    migration.reset_mcp_authorizations
    post '/mcp', params: {jsonrpc: '2.0', id: 1, method: 'initialize', params: {}}.to_json,
      headers: {'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access}"}
    assert_response :unauthorized
    post '/oauth/token', params: {grant_type: 'refresh_token', client_id: old.client_id, refresh_token: refresh}
    assert_response :bad_request
    assert_equal 'invalid_grant', JSON.parse(response.body)['error']
    assert_equal 0, McpOauthToken.count
    assert_equal 0, McpOauthAuthCode.count
    assert_not Doorkeeper::Application.exists?(app.id)
    assert_not Doorkeeper::AccessToken.exists?(token.id)
    assert_not Doorkeeper::AccessGrant.exists?(grant.id)
    assert Doorkeeper::Application.exists?(other.id)
    assert Doorkeeper::AccessToken.exists?(other_token.id)
    assert_equal 1, McpOauthClient.count # Metadata for audit only.
    assert_not_equal old.client_id, register['client_id']
    assert_equal 2, Doorkeeper::Application.count
  end
end
