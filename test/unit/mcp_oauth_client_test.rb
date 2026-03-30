# frozen_string_literal: true

require File.expand_path("../../test_helper", __FILE__)

class McpOauthClientTest < ActiveSupport::TestCase
  def setup
    McpOauthClient.delete_all
  end

  def test_redirect_uris_round_trip
    client = McpOauthClient.create!(
      client_id: SecureRandom.uuid,
      redirect_uris: ["https://example.com/cb"],
      client_id_issued_at: Time.current.to_i
    )
    assert_equal ["https://example.com/cb"], client.redirect_uris
  end

  def test_redirect_uris_defaults_on_bad_json
    client = McpOauthClient.new
    client.redirect_uris_json = "not json"
    assert_equal [], client.redirect_uris
  end

  def test_grant_types_default
    client = McpOauthClient.new
    client.grant_types_json = nil
    assert_equal ["authorization_code"], client.grant_types
  end

  def test_response_types_default
    client = McpOauthClient.new
    client.response_types_json = nil
    assert_equal ["code"], client.response_types
  end

  def test_to_registration_response_contains_required_fields
    client = McpOauthClient.create!(
      client_id: SecureRandom.uuid,
      client_name: "Test Client",
      redirect_uris: ["https://example.com/cb"],
      client_id_issued_at: Time.current.to_i
    )
    resp = client.to_registration_response
    assert_includes resp.keys, :client_id
    assert_includes resp.keys, :redirect_uris
    assert_includes resp.keys, :client_name
  end

  def test_client_id_uniqueness
    uuid = SecureRandom.uuid
    McpOauthClient.create!(client_id: uuid, redirect_uris: [], client_id_issued_at: 0)
    dup = McpOauthClient.new(client_id: uuid, redirect_uris: [], client_id_issued_at: 0)
    assert_not dup.valid?
  end
end
