class McpOauthClient < ActiveRecord::Base
  validates :client_id, presence: true, uniqueness: true

  def redirect_uris
    JSON.parse(redirect_uris_json)
  rescue
    []
  end

  def redirect_uris=(arr)
    self.redirect_uris_json = arr.to_json
  end

  def grant_types
    JSON.parse(grant_types_json)
  rescue
    ['authorization_code']
  end

  def grant_types=(arr)
    self.grant_types_json = arr.to_json
  end

  def response_types
    JSON.parse(response_types_json)
  rescue
    ['code']
  end

  def response_types=(arr)
    self.response_types_json = arr.to_json
  end

  def to_registration_response
    {
      client_id: client_id,
      client_id_issued_at: client_id_issued_at,
      client_name: client_name,
      redirect_uris: redirect_uris,
      grant_types: grant_types,
      response_types: response_types,
      token_endpoint_auth_method: token_endpoint_auth_method
    }.compact
  end
end
