# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpOauthAuthCodeTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    McpOauthAuthCode.delete_all
  end

  def build_code(overrides = {})
    McpOauthAuthCode.create!({
      code: SecureRandom.hex(20),
      client_id: SecureRandom.uuid,
      user_id: User.find(1).id,
      redirect_uri: "https://example.com/cb",
      code_challenge: "abc123",
      code_challenge_method: "S256",
      scopes: "mcp:tools",
      expires_at: 10.minutes.from_now
    }.merge(overrides))
  end

  def test_active_scope_returns_non_expired
    code = build_code
    assert_includes McpOauthAuthCode.active, code
  end

  def test_active_scope_excludes_expired
    code = build_code(expires_at: 1.second.ago)
    assert_not_includes McpOauthAuthCode.active, code
  end

  def test_expired_true
    code = build_code(expires_at: 1.second.ago)
    assert code.expired?
  end

  def test_expired_false
    code = build_code
    assert_not code.expired?
  end
end
