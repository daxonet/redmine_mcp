# frozen_string_literal: true

class UnifyMcpOauth < ActiveRecord::Migration[7.2]
  def up
    add_column :oauth_access_tokens, :mcp_refresh_expires_at, :datetime unless column_exists?(:oauth_access_tokens, :mcp_refresh_expires_at)
    Doorkeeper::AccessToken.reset_column_information
    require_relative '../../lib/redmine_mcp/legacy_oauth_import'
    RedmineMcp::LegacyOauthImport.run!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, 'Restore the pre-upgrade database and old application together; hashed credentials cannot be reconstructed.'
  end
end
