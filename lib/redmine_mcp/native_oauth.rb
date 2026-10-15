# frozen_string_literal: true

module RedmineMcp
  module NativeOauth
    SCOPE = 'mcp_tools'

    def self.mcp?(record)
      record && record.scopes.to_s.split.include?(SCOPE)
    end

    # Only MCP applications are affected; other Redmine OAuth clients retain
    # the server's existing policy.
    module AuthorizationPolicy
      def new
        return unless valid_mcp_authorization?
        super
      end

      def create
        return unless valid_mcp_authorization?
        super
      end

      private

      def valid_mcp_authorization?
        app = Doorkeeper::Application.find_by(uid: params[:client_id])
        return true unless NativeOauth.mcp?(app)
        params[:scope] = SCOPE if params[:scope].blank? || params[:scope] == 'mcp:tools'
        challenge = params[:code_challenge].to_s
        return true if params[:code_challenge_method] == 'S256' && challenge.match?(/\A[A-Za-z0-9_-]{43}\z/)
        render json: {error: 'invalid_request', error_description: 'MCP requires S256 PKCE'}, status: :bad_request
        false
      end
    end

    module TokenPolicy
      def create
        if params[:scope] == 'mcp:tools'
          params[:scope] = SCOPE
          request.parameters['scope'] = SCOPE
        end
        record = case params[:grant_type]
                 when 'refresh_token'
                   Doorkeeper::AccessToken.by_refresh_token(params[:refresh_token].to_s)
                 when 'authorization_code'
                   Doorkeeper::AccessGrant.by_token(params[:code].to_s)
                 end
        if NativeOauth.mcp?(record)
          user = User.find_by(id: record.resource_owner_id)
          expired_refresh = params[:grant_type] == 'refresh_token' &&
            record.mcp_refresh_expires_at && record.mcp_refresh_expires_at <= Time.current
          bad_pkce = record.is_a?(Doorkeeper::AccessGrant) && record.code_challenge_method != 'S256'
          if !user&.active? || expired_refresh || bad_pkce
            render json: {error: 'invalid_grant'}, status: :bad_request
            return
          end
        end
        super
      end
    end

    module RefreshPolicy
      private

      def refresh_token_revoked_on_use?
        NativeOauth.mcp?(refresh_token) ? false : super
      end
    end

    module TokenLifetime
      def generate_refresh_token
        super
        if NativeOauth.mcp?(self)
          self.mcp_refresh_expires_at ||= 30.days.from_now
          self.expires_in = 3600
        end
      end
    end
  end
end

Rails.application.config.after_initialize do
  Doorkeeper::AuthorizationsController.prepend(RedmineMcp::NativeOauth::AuthorizationPolicy) unless
    Doorkeeper::AuthorizationsController < RedmineMcp::NativeOauth::AuthorizationPolicy
  Doorkeeper::TokensController.prepend(RedmineMcp::NativeOauth::TokenPolicy) unless
    Doorkeeper::TokensController < RedmineMcp::NativeOauth::TokenPolicy
  Doorkeeper::OAuth::RefreshTokenRequest.prepend(RedmineMcp::NativeOauth::RefreshPolicy) unless
    Doorkeeper::OAuth::RefreshTokenRequest < RedmineMcp::NativeOauth::RefreshPolicy
  Doorkeeper::AccessToken.prepend(RedmineMcp::NativeOauth::TokenLifetime) unless
    Doorkeeper::AccessToken < RedmineMcp::NativeOauth::TokenLifetime
end

class McpNativeOauthHooks < Redmine::Hook::ViewListener
  render_on :view_layouts_base_content, partial: 'mcp_oauth/application_authorizations'
end

Rails.application.config.filter_parameters += %i[access_token refresh_token code code_verifier client_secret]
