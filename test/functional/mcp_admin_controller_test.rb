# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpAdminControllerTest < Redmine::ControllerTest
  fixtures :users

  def setup
    McpOauthToken.delete_all
    McpOauthClient.delete_all
    @request.session[:user_id] = 1 # admin
  end

  def test_index_requires_admin
    @request.session[:user_id] = 2 # non-admin
    get "/admin/mcp/tokens"
    assert_response :forbidden
  end

  def test_index_shows_tokens
    get "/admin/mcp/tokens"
    assert_response :success
  end

  def test_index_filters_by_status_active
    create_token(expires_at: 1.hour.from_now)
    create_token(expires_at: 1.second.ago)
    get "/admin/mcp/tokens", params: { status: "active" }
    assert_response :success
    assert_equal 1, assigns(:token_count)
  end

  def test_index_filters_by_status_expired
    create_token(expires_at: 1.hour.from_now)
    create_token(expires_at: 1.second.ago)
    get "/admin/mcp/tokens", params: { status: "expired" }
    assert_response :success
    assert_equal 1, assigns(:token_count)
  end

  def test_index_paginates
    5.times { create_token }
    get "/admin/mcp/tokens", params: { per_page: 25 }
    assert_response :success
    assert_equal 5, assigns(:token_count)
  end

  def test_destroy_revokes_token
    token = create_token
    delete "/admin/mcp/tokens/#{token.id}"
    assert_response :redirect
    assert_nil McpOauthToken.find_by(id: token.id)
  end

  def test_update_settings_adds_uri
    post "/admin/mcp/settings",
         params: { allowed_redirect_uris: "", new_uri: "https://example.com/cb", add_uri: "1" }
    assert_response :redirect
    uris = Setting.plugin_redmine_mcp["allowed_redirect_uris"]
    assert_includes uris, "https://example.com/cb"
  end

  def test_update_settings_removes_uri
    Setting.plugin_redmine_mcp = { "allowed_redirect_uris" => "https://example.com/cb" }
    post "/admin/mcp/settings",
         params: { allowed_redirect_uris: "" }
    assert_response :redirect
    uris = Setting.plugin_redmine_mcp["allowed_redirect_uris"].to_s
    assert_not_includes uris, "https://example.com/cb"
  end

  private

  def create_token(overrides = {})
    McpOauthToken.create!({
      access_token: SecureRandom.hex(32),
      refresh_token: SecureRandom.hex(32),
      client_id: SecureRandom.uuid,
      user_id: 1,
      scopes: "mcp:tools",
      expires_at: 1.hour.from_now,
      refresh_expires_at: 30.days.from_now
    }.merge(overrides))
  end
end
