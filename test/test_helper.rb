# frozen_string_literal: true

# CI installs the plugin through a symlink to a separate checkout. __dir__
# therefore is not necessarily below REDMINE_ROOT/plugins.
redmine_root = ENV['REDMINE_HOME'] ||
               (defined?(Rails) && Rails.respond_to?(:root) && Rails.root) ||
               File.expand_path('../../..', __dir__)
require File.join(redmine_root.to_s, 'test', 'test_helper')

module McpTestSetup
  CALLBACK = 'https://example.com/cb'
  SCOPES = 'view_issues view_project add_issues'

  def mcp_settings(extra = {})
    Setting.plugin_redmine_mcp = {'allowed_redirect_uris' => CALLBACK, 'cimd_trusted_hosts' => '',
                                  'scopes' => SCOPES}.merge(extra)
  end

  def reset_oauth_tables
    McpOauthToken.delete_all
    McpOauthAuthCode.delete_all
    McpOauthClient.delete_all
    Doorkeeper::AccessGrant.delete_all
    Doorkeeper::AccessToken.delete_all
    Doorkeeper::Application.delete_all
  end

  def pkce
    verifier = SecureRandom.hex(32)
    [verifier, Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)]
  end

  def query_of(location)
    URI.decode_www_form(URI.parse(location).query.to_s).to_h
  end
end
