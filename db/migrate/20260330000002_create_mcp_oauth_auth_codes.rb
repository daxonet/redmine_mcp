class CreateMcpOauthAuthCodes < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_oauth_auth_codes do |t|
      t.string  :code,                   null: false, index: { unique: true }
      t.string  :client_id,              null: false
      t.integer :user_id,                null: false
      t.string  :redirect_uri,           null: false
      t.string  :code_challenge,         null: false
      t.string  :code_challenge_method,  null: false, default: 'S256'
      t.string  :scopes,                 null: false, default: ''
      t.string  :state
      t.datetime :expires_at,            null: false
      t.timestamps null: false
    end
  end
end
