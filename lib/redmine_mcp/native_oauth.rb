# frozen_string_literal: true

module RedmineMcp
  module NativeOauth
    # Scope of applications created by redmine_mcp 1.x. Still recognised so
    # leftover applications keep the MCP policies until they are removed.
    SCOPE = 'mcp_tools'

    # An MCP application is one this plugin registered (DCR or CIMD), or a
    # legacy 1.x application. Other Redmine OAuth clients keep Redmine's
    # default policy. Accepts an application, grant or token.
    def self.mcp?(record)
      app = record.is_a?(Doorkeeper::Application) ? record : record&.application
      return false unless app

      app.mcp_registration_key.present? || app.scopes.to_s.split.include?(SCOPE)
    end

    # MCP clients usually ask for every advertised scope, an old 1.x scope, or
    # nothing. Grant what they ask for within the application's scopes, and
    # all of the application's scopes when the request names none of them.
    def self.effective_scope(app, requested)
      granted = app.scopes.to_s.split
      picked = requested.to_s.split & granted
      (picked.presence || granted).join(' ')
    end

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
        client_id = params[:client_id].to_s
        if ClientMetadataDocument.candidate?(client_id)
          begin
            ClientMetadataDocument.resolve!(client_id)
          rescue ClientMetadataDocument::Invalid => e
            Rails.logger.warn("[redmine_mcp] CIMD client #{client_id} rejected: #{e.message}")
            render json: {error: 'invalid_client', error_description: e.message}, status: :bad_request
            return false
          end
        end
        app = Doorkeeper::Application.find_by(uid: client_id)
        return true unless NativeOauth.mcp?(app)
        params[:scope] = NativeOauth.effective_scope(app, params[:scope])
        challenge = params[:code_challenge].to_s
        return true if params[:code_challenge_method] == 'S256' && challenge.match?(/\A[A-Za-z0-9_-]{43}\z/)
        render json: {error: 'invalid_request', error_description: 'MCP requires S256 PKCE'}, status: :bad_request
        false
      end
    end

    module TokenPolicy
      def create
        # Old clients may still send the retired 1.x scope on refresh.
        if Backend::LEGACY_SCOPES.include?(params[:scope].to_s)
          params.delete(:scope)
          request.parameters.delete('scope')
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
  checker = Doorkeeper::OAuth::Helpers::URIChecker.singleton_class
  checker.prepend(RedmineMcp::RedirectPolicy::LocalhostLoopback) unless
    checker < RedmineMcp::RedirectPolicy::LocalhostLoopback
end

class McpNativeOauthHooks < Redmine::Hook::ViewListener
  render_on :view_layouts_base_content, partial: 'mcp_oauth/application_authorizations'
end

Rails.application.config.filter_parameters += %i[access_token refresh_token code code_verifier client_secret]
