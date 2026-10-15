# frozen_string_literal: true

class ResetMcpClientsForReconnection < ActiveRecord::Migration[7.2]
  def up
    add_column :oauth_applications, :mcp_registration_key, :string, limit: 64
    add_index :oauth_applications, :mcp_registration_key, unique: true
    Doorkeeper::Application.reset_column_information
    reset_mcp_authorizations
  end

  def reset_mcp_authorizations
    # The owner chose a clean reconnect over retaining historical registrations.
    # Preserve unrelated native OAuth applications (including Azure SSO).
    Doorkeeper::Application.transaction do
      legacy = Doorkeeper::Application.where(uid: McpOauthClient.select(:client_id))
      only_mcp = Doorkeeper::Application.where(scopes: %w[mcp_tools mcp:tools])
      legacy.or(only_mcp).find_each(&:destroy!)
      # Legacy clients remain as audit metadata only; no old code/token survives.
      McpOauthAuthCode.delete_all
      McpOauthToken.delete_all
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Restore the matching pre-upgrade database and application; users must reconnect after upgrade.'
  end
end
