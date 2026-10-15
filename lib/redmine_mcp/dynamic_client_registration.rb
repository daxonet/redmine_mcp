# frozen_string_literal: true
require 'digest'
require 'json'

module RedmineMcp
  # Public clients can share an application; grants/tokens remain per user.
  # A database unique key makes retried/concurrent registrations idempotent.
  class DynamicClientRegistration
    def self.register!(name:, redirect_uris:)
      attributes = {name: name, redirect_uri: redirect_uris.uniq.sort.join("\n"),
                    scopes: 'mcp_tools', confidential: false}
      key = Digest::SHA256.hexdigest(JSON.generate(attributes))
      existing = Doorkeeper::Application.find_by(mcp_registration_key: key)
      if existing
        existing.with_lock do
          # An administrator may have edited the application since registration.
          # Never return a client with metadata different from the validated request.
          matches = existing.name == attributes[:name] &&
            existing.redirect_uri == attributes[:redirect_uri] &&
            existing.scopes.to_s == attributes[:scopes] && !existing.confidential?
          return existing if matches
          existing.update_column(:mcp_registration_key, nil)
        end
      end
      Doorkeeper::Application.create_or_find_by!(mcp_registration_key: key) do |app|
        app.assign_attributes(attributes)
      end
    end
  end
end
