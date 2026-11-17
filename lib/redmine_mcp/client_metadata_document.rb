# frozen_string_literal: true
require 'digest'
require 'json'
require 'net/http'

module RedmineMcp
  # OAuth Client ID Metadata Documents (CIMD), as used by the MCP
  # authorization spec: the client_id is an https URL whose JSON document
  # describes the client. Claude and ChatGPT prefer this over DCR.
  #
  # Only documents on administrator-trusted hosts are fetched. The client is
  # materialised as a public Doorkeeper application whose uid is the URL, so
  # Doorkeeper's normal authorization and token code handles the rest.
  module ClientMetadataDocument
    class Invalid < StandardError; end

    MAX_BYTES = 16_384
    TIMEOUT = 3
    REFRESH_AFTER = 1.hour

    module_function

    def trusted_hosts
      RedmineMcp.setting_lines('cimd_trusted_hosts').map(&:downcase)
    end

    def enabled?
      trusted_hosts.any?
    end

    def candidate?(client_id)
      uri = parse(client_id)
      uri && host_trusted?(uri.host)
    end

    def host_trusted?(host)
      host = host.to_s.downcase
      trusted_hosts.any? do |trusted|
        trusted.start_with?('*.') ? host.end_with?(trusted[1..]) : host == trusted
      end
    end

    def registration_key(client_id)
      Digest::SHA256.hexdigest("cimd\n#{client_id}")
    end

    # Returns the Doorkeeper application for a trusted CIMD client_id,
    # creating or refreshing it from the published document when needed.
    def resolve!(client_id)
      key = registration_key(client_id)
      scopes = Backend.scope_string
      raise Invalid, 'MCP server is not enabled' if scopes.blank?

      app = Doorkeeper::Application.find_by(uid: client_id)
      raise Invalid, 'client_id is used by a manually created application' if app && app.mcp_registration_key != key
      return app if app && app.scopes.to_s == scopes && app.updated_at > REFRESH_AFTER.ago

      attributes = metadata_attributes(client_id, fetch(client_id)).merge(scopes: scopes, confidential: false)
      if app
        app.update!(attributes)
        app.touch
        app
      else
        Doorkeeper::Application.create!(attributes.merge(uid: client_id, mcp_registration_key: key))
      end
    rescue ActiveRecord::RecordNotUnique
      Doorkeeper::Application.find_by!(uid: client_id)
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, e.message
    end

    def metadata_attributes(client_id, document)
      raise Invalid, 'metadata document must be a JSON object' unless document.is_a?(Hash)
      raise Invalid, 'client_id does not match the document URL' unless document['client_id'] == client_id

      uris = document['redirect_uris']
      unless uris.is_a?(Array) && uris.size.between?(1, 10) && uris.all? { |u| u.is_a?(String) && RedirectPolicy.safe?(u) }
        raise Invalid, 'redirect_uris are missing or unsafe'
      end
      unless [nil, 'none'].include?(document['token_endpoint_auth_method'])
        raise Invalid, 'only public clients (token_endpoint_auth_method "none") are supported'
      end
      grant_types = Array(document['grant_types'] || ['authorization_code'])
      raise Invalid, 'unsupported grant_types' unless (grant_types - %w[authorization_code refresh_token]).empty?
      raise Invalid, 'unsupported response_types' unless Array(document['response_types'] || ['code']) == ['code']

      name = document['client_name'].is_a?(String) ? document['client_name'].strip.presence : nil
      {name: (name || parse(client_id).host).truncate(255), redirect_uri: uris.uniq.join("\n")}
    end

    def fetch(client_id)
      uri = parse(client_id)
      raise Invalid, 'untrusted client metadata host' unless uri && host_trusted?(uri.host)

      body = +''
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: TIMEOUT, read_timeout: TIMEOUT,
                      write_timeout: TIMEOUT) do |http|
        request = Net::HTTP::Get.new(uri)
        request['Accept'] = 'application/json'
        http.request(request) do |response|
          raise Invalid, "metadata document returned HTTP #{response.code}" unless response.is_a?(Net::HTTPOK)

          response.read_body do |chunk|
            body << chunk
            raise Invalid, 'metadata document is too large' if body.bytesize > MAX_BYTES
          end
        end
      end
      JSON.parse(body)
    rescue JSON::ParserError
      raise Invalid, 'metadata document is not valid JSON'
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse => e
      raise Invalid, "metadata document could not be fetched (#{e.class.name})"
    end

    # https, default port, a path, and nothing that could smuggle another target.
    def parse(client_id)
      return nil unless client_id.is_a?(String) && client_id.length <= 255

      uri = URI.parse(client_id)
      return nil unless uri.is_a?(URI::HTTPS) && uri.host.present? && uri.port == 443
      return nil if uri.userinfo || uri.fragment || uri.query || uri.path.to_s.length < 2

      uri
    rescue URI::InvalidURIError
      nil
    end
  end
end
