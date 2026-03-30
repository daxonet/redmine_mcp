# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpOauthFlowTest < Redmine::IntegrationTest
  fixtures :users

  def setup
    McpOauthClient.delete_all
    McpOauthToken.delete_all
    McpOauthAuthCode.delete_all
  end

  def test_full_oauth_flow
    # 1. Register a client via DCR
    post "/mcp/oauth/register",
         params: {
           client_name: "Integration Test Client",
           redirect_uris: ["https://example.com/cb"],
           grant_types: ["authorization_code"],
           response_types: ["code"],
           token_endpoint_auth_method: "none"
         }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :created
    client_id = JSON.parse(response.body)["client_id"]
    assert client_id.present?

    # 2. Generate PKCE parameters
    verifier  = SecureRandom.hex(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    # 3. Request authorization (should redirect to consent page)
    get "/mcp/oauth/authorize",
        params: {
          client_id: client_id,
          redirect_uri: "https://example.com/cb",
          response_type: "code",
          code_challenge: challenge,
          code_challenge_method: "S256",
          state: "teststate",
          scope: "mcp:tools"
        }
    assert_response :redirect
    assert_match %r{/mcp/consent}, response.location

    # 4. Login as admin
    log_user("admin", "admin")

    # 5. POST consent (authorize)
    post "/mcp/consent",
         params: {
           client_id: client_id,
           redirect_uri: "https://example.com/cb",
           code_challenge: challenge,
           code_challenge_method: "S256",
           state: "teststate",
           scope: "mcp:tools",
           authorize: "1"
         }
    assert_response :redirect
    location = response.location
    assert_match(/code=/, location)
    assert_match(/state=teststate/, location)

    code = URI.decode_www_form(URI.parse(location).query).to_h["code"]

    # 6. Exchange code for token
    post "/mcp/oauth/token",
         params: {
           grant_type: "authorization_code",
           code: code,
           code_verifier: verifier,
           client_id: client_id,
           redirect_uri: "https://example.com/cb"
         }
    assert_response :success
    token_response = JSON.parse(response.body)
    assert token_response["access_token"].present?
    assert token_response["refresh_token"].present?

    # 7. Verify code cannot be reused
    post "/mcp/oauth/token",
         params: {
           grant_type: "authorization_code",
           code: code,
           code_verifier: verifier,
           client_id: client_id,
           redirect_uri: "https://example.com/cb"
         }
    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]

    # 8. Refresh token rotation
    post "/mcp/oauth/token",
         params: {
           grant_type: "refresh_token",
           refresh_token: token_response["refresh_token"],
           client_id: client_id
         }
    assert_response :success
    new_token_response = JSON.parse(response.body)
    assert new_token_response["access_token"].present?
    assert_not_equal token_response["access_token"], new_token_response["access_token"]

    # 9. Old refresh token is now invalid
    post "/mcp/oauth/token",
         params: {
           grant_type: "refresh_token",
           refresh_token: token_response["refresh_token"],
           client_id: client_id
         }
    assert_response :bad_request
    assert_equal "invalid_grant", JSON.parse(response.body)["error"]
  end
end
