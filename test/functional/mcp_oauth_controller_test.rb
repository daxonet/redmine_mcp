# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpOauthControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    McpOauthClient.delete_all
    McpOauthToken.delete_all
    McpOauthAuthCode.delete_all
  end

  # ── Discovery endpoints ──────────────────────────────────────────────────────

  def test_authorization_server_metadata
    get "/.well-known/oauth-authorization-server"
    assert_response :success
    json = JSON.parse(response.body)
    assert_includes json["grant_types_supported"], "authorization_code"
    assert_includes json["code_challenge_methods_supported"], "S256"
  end

  def test_protected_resource_metadata
    get "/.well-known/oauth-protected-resource"
    assert_response :success
    json = JSON.parse(response.body)
    assert json["resource"].end_with?("/mcp")
  end

  # ── Dynamic Client Registration ──────────────────────────────────────────────

  def test_register_creates_client
    post "/mcp/oauth/register",
         params: {
           client_name: "Test",
           redirect_uris: ["https://example.com/cb"],
           grant_types: ["authorization_code"],
           response_types: ["code"],
           token_endpoint_auth_method: "none"
         }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :created
    json = JSON.parse(response.body)
    assert json["client_id"].present?
  end

  def test_register_requires_redirect_uris
    post "/mcp/oauth/register",
         params: { client_name: "Test" }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_redirect_uri", json["error"]
  end

  def test_register_blocked_by_trusted_uri_whitelist
    Setting.plugin_redmine_mcp = { "allowed_redirect_uris" => "https://allowed.example.com/cb" }
    post "/mcp/oauth/register",
         params: {
           client_name: "Test",
           redirect_uris: ["https://evil.example.com/cb"]
         }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_redirect_uri", json["error"]
  ensure
    Setting.plugin_redmine_mcp = {}
  end

  # ── Token endpoint ───────────────────────────────────────────────────────────

  def test_token_rejects_unknown_grant_type
    post "/mcp/oauth/token", params: { grant_type: "password" }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "unsupported_grant_type", json["error"]
  end

  def test_token_rejects_invalid_auth_code
    post "/mcp/oauth/token",
         params: {
           grant_type: "authorization_code",
           code: "invalid",
           code_verifier: "verifier",
           client_id: "cid",
           redirect_uri: "https://example.com/cb"
         }
    assert_response :bad_request
    json = JSON.parse(response.body)
    assert_equal "invalid_grant", json["error"]
  end

  def test_token_exchanges_valid_auth_code
    user = User.find(1)
    verifier = SecureRandom.hex(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    client_id = SecureRandom.uuid
    redirect_uri = "https://example.com/cb"

    McpOauthAuthCode.create!(
      code: "testcode123",
      client_id: client_id,
      user_id: user.id,
      redirect_uri: redirect_uri,
      code_challenge: challenge,
      code_challenge_method: "S256",
      scopes: "mcp:tools",
      expires_at: 10.minutes.from_now
    )

    post "/mcp/oauth/token",
         params: {
           grant_type: "authorization_code",
           code: "testcode123",
           code_verifier: verifier,
           client_id: client_id,
           redirect_uri: redirect_uri
         }
    assert_response :success
    json = JSON.parse(response.body)
    assert json["access_token"].present?
    assert json["refresh_token"].present?
    assert_equal 3600, json["expires_in"]
  end
end
