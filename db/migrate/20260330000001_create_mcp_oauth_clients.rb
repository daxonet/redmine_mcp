class CreateMcpOauthClients < ActiveRecord::Migration[7.0]
  def change
    create_table :mcp_oauth_clients do |t|
      t.string  :client_id,                  null: false, index: { unique: true }
      t.string  :client_name
      t.text    :redirect_uris_json,          null: false, default: '[]'
      t.text    :grant_types_json,            null: false, default: '["authorization_code"]'
      t.text    :response_types_json,         null: false, default: '["code"]'
      t.string  :token_endpoint_auth_method,  null: false, default: 'none'
      t.integer :client_id_issued_at
      t.timestamps null: false
    end
  end
end
