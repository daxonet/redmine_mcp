class McpOauthAuthCode < ActiveRecord::Base
  belongs_to :user

  scope :active, -> { where('expires_at > ?', Time.current) }

  def expired?
    expires_at <= Time.current
  end
end
