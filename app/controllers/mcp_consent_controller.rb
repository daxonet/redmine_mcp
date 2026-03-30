class McpConsentController < ApplicationController
  skip_before_action :verify_authenticity_token, only: [:create]

  layout false

  # GET /mcp/consent
  def new
    # Redirect anonymous users to Redmine's login page.
    # back_url includes all OAuth query params so they survive session reset.
    unless User.current.logged?
      redirect_to signin_path(back_url: request.url) and return
    end

    @oauth = extract_oauth_params
    unless @oauth
      render plain: 'Invalid or expired authorization request.', status: :bad_request
      return
    end

    @client_name  = McpOauthClient.find_by(client_id: @oauth[:client_id])&.client_name || 'Claude AI'
    @app_title    = Setting.app_title.presence || 'Redmine'
    @current_user = User.current
  end

  # POST /mcp/consent
  def create
    unless User.current.logged?
      redirect_to signin_path(back_url: request.url) and return
    end

    @oauth = extract_oauth_params
    unless @oauth
      render plain: 'Invalid or expired authorization request.', status: :bad_request
      return
    end

    if params[:deny].present?
      redirect_uri = build_redirect_uri(@oauth[:redirect_uri],
        error: 'access_denied', state: @oauth[:state])
      redirect_to redirect_uri, allow_other_host: true
      return
    end

    auth_code = McpOauthAuthCode.create!(
      code:                  SecureRandom.hex(32),
      client_id:             @oauth[:client_id],
      user_id:               User.current.id,
      redirect_uri:          @oauth[:redirect_uri],
      code_challenge:        @oauth[:code_challenge],
      code_challenge_method: @oauth[:code_challenge_method],
      scopes:                @oauth[:scope],
      state:                 @oauth[:state],
      expires_at:            10.minutes.from_now
    )

    redirect_to build_redirect_uri(@oauth[:redirect_uri],
      code: auth_code.code, state: @oauth[:state]), allow_other_host: true
  end

  private

  def extract_oauth_params
    client_id    = params[:client_id].presence
    redirect_uri = params[:redirect_uri].presence
    code_challenge = params[:code_challenge].presence
    return nil unless client_id && redirect_uri && code_challenge

    client = McpOauthClient.find_by(client_id: client_id)
    return nil unless client&.redirect_uris&.include?(redirect_uri)

    {
      client_id:             client_id,
      redirect_uri:          redirect_uri,
      code_challenge:        code_challenge,
      code_challenge_method: params[:code_challenge_method].presence || 'S256',
      state:                 params[:state],
      scope:                 params[:scope].presence || 'mcp:tools'
    }
  end

  def build_redirect_uri(base_uri, extra_params)
    uri = URI.parse(base_uri)
    query = URI.decode_www_form(uri.query.to_s)
    extra_params.each do |k, v|
      query << [k.to_s, v.to_s] if v.present?
    end
    uri.query = URI.encode_www_form(query)
    uri.to_s
  end
end
