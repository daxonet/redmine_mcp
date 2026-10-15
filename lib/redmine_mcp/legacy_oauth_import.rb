# frozen_string_literal: true

module RedmineMcp
  # Retain legacy tables for audit/backup only. No runtime fallback accepts them.
  # Never rerun this import after users revoke native authorizations.
  class LegacyOauthImport
    def self.run!
      Doorkeeper::Application.transaction do
        McpOauthClient.find_each do |client|
          raise "OAuth client UID collision: #{client.id}" if Doorkeeper::Application.exists?(uid: client.client_id)
          # Old implementation never issued client secrets: all clients are public.
          Doorkeeper::Application.create!(uid: client.client_id,
            name: client.client_name.presence || 'Migrated MCP client',
            redirect_uri: client.redirect_uris.join("\n"), scopes: 'mcp_tools', confidential: false)
        end
        McpOauthToken.find_each do |old|
          app = Doorkeeper::Application.find_by!(uid: old.client_id)
          next unless User.exists?(id: old.user_id)
          next unless old.expires_at > Time.current || old.refresh_expires_at&.>(Time.current)
          # Insert the server's hashed representation directly. Doorkeeper create
          # callbacks would generate different secrets and disconnect clients.
          attrs = {application_id: app.id, resource_owner_id: old.user_id,
            token: Doorkeeper::AccessToken.secret_strategy.transform_secret(old.access_token),
            refresh_token: old.refresh_token.present? && old.refresh_expires_at&.>(Time.current) ?
              Doorkeeper::AccessToken.secret_strategy.transform_secret(old.refresh_token) : nil,
            scopes: 'mcp_tools', created_at: old.created_at,
            expires_in: [(old.expires_at - old.created_at).to_i, 0].max,
            mcp_refresh_expires_at: old.refresh_expires_at, previous_refresh_token: ''}
          Doorkeeper::AccessToken.insert_all!([attrs])
        end
        McpOauthAuthCode.where('expires_at > ?', Time.current).find_each do |old|
          app = Doorkeeper::Application.find_by!(uid: old.client_id)
          next unless User.exists?(id: old.user_id)
          Doorkeeper::AccessGrant.insert_all!([{application_id: app.id, resource_owner_id: old.user_id,
            token: Doorkeeper::AccessGrant.secret_strategy.transform_secret(old.code),
            redirect_uri: old.redirect_uri, scopes: 'mcp_tools', created_at: old.created_at,
            expires_in: [(old.expires_at - old.created_at).to_i, 0].max,
            code_challenge: old.code_challenge, code_challenge_method: old.code_challenge_method}])
        end
      end
    end
  end
end
