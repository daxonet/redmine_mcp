# frozen_string_literal: true

module RedmineMcp
  # The MCP endpoint itself (/mcp) is served by RedmineUP Agent. This plugin
  # only provides discovery, client registration and OAuth policy for it.
  module Backend
    LEGACY_SCOPES = %w[mcp_tools mcp:tools].freeze
    # Never hand out Redmine administrator rights to self-registered clients.
    FORBIDDEN_SCOPES = %w[admin].freeze

    module_function

    def installed?
      Redmine::Plugin.installed?(:redmineup_agent)
    end

    def mcp_enabled?
      installed? && ::RedmineupAgent.mcp_enabled?
    end

    def available?
      mcp_enabled? && Setting.rest_api_enabled?
    end

    def configured_scopes
      RedmineMcp.setting('scopes').split(/[\s,]+/).reject(&:blank?)
    end

    # Scopes given to dynamically registered and CIMD clients. An empty
    # setting follows RedmineUP Agent's own MCP scope list.
    def scopes
      wanted = configured_scopes.presence || (installed? ? ::RedmineupAgent::Mcp.scopes : [])
      known = Doorkeeper.config.scopes.all.map(&:to_s)
      (wanted.map(&:to_s) & known) - FORBIDDEN_SCOPES - LEGACY_SCOPES
    end

    def scope_string
      scopes.uniq.sort.join(' ')
    end
  end

  def self.setting(name)
    Setting.plugin_redmine_mcp.to_h.fetch(name.to_s, '').to_s
  end

  def self.setting_lines(name)
    setting(name).lines.map(&:strip).reject { |line| line.blank? || line.start_with?('#') }
  end
end
