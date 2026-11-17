# frozen_string_literal: true
require 'uri'

module RedmineMcp
  # Which callback URLs a self-registering (DCR) client may use.
  #
  # Each configured line is an exact URL, or a URL where "*" stands for one
  # run of characters without "/", "?", "#" or "@", e.g.
  #   https://chatgpt.com/connector/oauth/*
  #   http://localhost:*/callback
  module RedirectPolicy
    LOOPBACK_HOSTS = %w[localhost 127.0.0.1 [::1] ::1].freeze

    module_function

    def patterns
      RedmineMcp.setting_lines('allowed_redirect_uris')
    end

    def allowed?(uri)
      uri.is_a?(String) && safe?(uri) && patterns.any? { |pattern| match?(pattern, uri) }
    end

    def match?(pattern, uri)
      return pattern == uri unless pattern.include?('*')

      regex = Regexp.escape(pattern).gsub('\*', '[^/?#@\s]+')
      /\A#{regex}\z/.match?(uri)
    end

    # https anywhere, plain http only for loopback; no credentials or fragments.
    def safe?(value)
      uri = URI.parse(value)
      uri.host.present? && uri.userinfo.nil? && uri.fragment.nil? &&
        (uri.scheme == 'https' || (uri.scheme == 'http' && LOOPBACK_HOSTS.include?(uri.host.downcase)))
    rescue URI::InvalidURIError
      false
    end

    # Doorkeeper ignores the port only for IP loopback addresses (RFC 8252
    # 7.3). Native clients such as Claude Code also register
    # http://localhost/callback and then listen on an ephemeral port.
    module LocalhostLoopback
      def loopback_uri?(uri)
        super || (uri.scheme == 'http' && uri.host.to_s.casecmp?('localhost'))
      end
    end
  end
end
