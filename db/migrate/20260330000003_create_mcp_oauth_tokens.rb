class CreateMcpOauthTokens < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_oauth_tokens do |t|
      t.string  :access_token,          null: false, index: { unique: true }
      t.string  :refresh_token,         index: { unique: true }
      t.string  :client_id,             null: false
      t.integer :user_id,               null: false
      t.string  :scopes,                null: false, default: ''
      t.datetime :expires_at,           null: false
      t.datetime :refresh_expires_at
      t.timestamps null: false
    end
  end
end
