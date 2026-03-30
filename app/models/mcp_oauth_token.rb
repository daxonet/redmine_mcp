class McpOauthToken < ActiveRecord::Base
  belongs_to :user

  scope :active_access, -> { where('expires_at > ?', Time.current) }
  scope :active_refresh, -> { where('refresh_expires_at > ?', Time.current) }

  def self.find_by_access_token(token)
    active_access.find_by(access_token: token)
  end

  def self.find_by_refresh_token(token)
    active_refresh.find_by(refresh_token: token)
  end

  def access_token_expired?
    expires_at <= Time.current
  end

  def scopes_array
    scopes.split
  end
end
