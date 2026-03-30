# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpOauthTokenTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    McpOauthToken.delete_all
  end

  def build_token(overrides = {})
    McpOauthToken.create!({
      access_token: SecureRandom.hex(32),
      refresh_token: SecureRandom.hex(32),
      client_id: SecureRandom.uuid,
      user_id: User.find(1).id,
      scopes: "mcp:tools",
      expires_at: 1.hour.from_now,
      refresh_expires_at: 30.days.from_now
    }.merge(overrides))
  end

  def test_find_by_access_token_returns_active
    token = build_token
    assert_equal token, McpOauthToken.find_by_access_token(token.access_token)
  end

  def test_find_by_access_token_ignores_expired
    token = build_token(expires_at: 1.second.ago)
    assert_nil McpOauthToken.find_by_access_token(token.access_token)
  end

  def test_find_by_refresh_token_returns_active
    token = build_token
    assert_equal token, McpOauthToken.find_by_refresh_token(token.refresh_token)
  end

  def test_find_by_refresh_token_ignores_expired_refresh
    token = build_token(refresh_expires_at: 1.second.ago)
    assert_nil McpOauthToken.find_by_refresh_token(token.refresh_token)
  end

  def test_access_token_expired_true
    token = build_token(expires_at: 1.second.ago)
    assert token.access_token_expired?
  end

  def test_access_token_expired_false
    token = build_token
    assert_not token.access_token_expired?
  end

  def test_scopes_array
    token = build_token(scopes: "mcp:tools read")
    assert_equal ["mcp:tools", "read"], token.scopes_array
  end
end
