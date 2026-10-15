# frozen_string_literal: true
class McpApplicationAuthorizationsController < ApplicationController
  before_action :require_admin
  def destroy
    app = Doorkeeper::Application.find(params[:application_id])
    return head :not_found unless RedmineMcp::NativeOauth.mcp?(app)
    Doorkeeper::AccessToken.transaction do
      Doorkeeper::AccessToken.revoke_all_for(app.id, params[:user_id].to_i)
      Doorkeeper::AccessGrant.where(application_id: app.id, resource_owner_id: params[:user_id].to_i, revoked_at: nil).update_all(revoked_at: Time.current)
    end
    flash[:notice] = 'MCP authorization revoked.'
    redirect_to oauth_application_path(app)
  end
end
