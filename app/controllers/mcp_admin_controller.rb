class McpAdminController < ApplicationController
  before_action :require_admin

  layout 'admin'
  helper :sort
  helper :mcp_admin
  include SortHelper

  PER_PAGE_OPTIONS = [25, 50, 100].freeze

  # GET /admin/mcp/tokens
  def index
    sort_init 'created_at', 'desc'
    sort_update %w[created_at expires_at client_id user_id]

    scope = McpOauthToken.includes(:user)

    # Filters
    if params[:user_id].present?
      scope = scope.where(user_id: params[:user_id].to_i)
    end
    if params[:client_name].present?
      client_ids = McpOauthClient
                     .where('client_name LIKE ?', "%#{params[:client_name]}%")
                     .pluck(:client_id)
      scope = scope.where(client_id: client_ids)
    end
    case params[:status]
    when 'active'  then scope = scope.where('expires_at > ?', Time.current)
    when 'expired' then scope = scope.where('expires_at <= ?', Time.current)
    end

    @token_count = scope.count
    @per_page    = (params[:per_page] || 25).to_i.clamp(25, 100)
    @page        = (params[:page] || 1).to_i
    @page_count  = [(@token_count.to_f / @per_page).ceil, 1].max
    @page        = @page.clamp(1, @page_count)

    @tokens      = scope.order(sort_clause).offset((@page - 1) * @per_page).limit(@per_page)
    client_ids   = @tokens.map(&:client_id).uniq
    @clients     = McpOauthClient.where(client_id: client_ids).index_by(&:client_id)

    # All users that have tokens (for filter dropdown)
    @token_users = User.where(id: McpOauthToken.select(:user_id).distinct)
                       .order(:login)

    @allowed_uris = allowed_uris_list
  end

  # POST /admin/mcp/settings
  def update_settings
    existing = params[:allowed_redirect_uris].to_s
                 .lines.map(&:strip).reject(&:blank?)
    if params[:add_uri].present?
      new_uri = params[:new_uri].to_s.strip
      existing << new_uri if new_uri.present? && !existing.include?(new_uri)
    end
    Setting.plugin_redmine_mcp = (Setting.plugin_redmine_mcp || {})
                                   .merge('allowed_redirect_uris' => existing.join("\n"))
    flash[:notice] = 'Trusted URLs updated.'
    redirect_to mcp_admin_tokens_path
  end

  # DELETE /admin/mcp/tokens/:id
  def destroy
    McpOauthToken.find(params[:id]).destroy
    flash[:notice] = 'Authorization revoked.'
    redirect_to mcp_admin_tokens_path(request.query_parameters.except('_method'))
  end

  # DELETE /admin/mcp/tokens  (revoke all for a user)
  def destroy_user
    McpOauthToken.where(user_id: params[:user_id].to_i).destroy_all
    flash[:notice] = 'All authorizations for user revoked.'
    redirect_to mcp_admin_tokens_path(request.query_parameters.except('_method', 'user_id'))
  end

  private

  def allowed_uris_list
    raw = Setting.plugin_redmine_mcp&.dig('allowed_redirect_uris').to_s
    raw.lines.map(&:strip).reject(&:blank?)
  end
end
