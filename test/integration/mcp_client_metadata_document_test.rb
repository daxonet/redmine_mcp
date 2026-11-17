# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)

class McpClientMetadataDocumentTest < Redmine::IntegrationTest
  include McpTestSetup
  fixtures :users, :email_addresses, :user_preferences

  CLIENT_ID = 'https://claude.ai/oauth/claude-code-client-metadata'
  LOOPBACK = 'http://localhost:3118/callback'
  CIMD = RedmineMcp::ClientMetadataDocument

  def setup
    super
    Setting.rest_api_enabled = '1'
    mcp_settings('cimd_trusted_hosts' => "claude.ai\n*.example.org")
    RedmineMcp::Backend.stubs(:available?).returns(true)
    reset_oauth_tables
    @verifier, @challenge = pkce
  end

  def document(extra = {})
    {'client_id' => CLIENT_ID, 'client_name' => 'Claude Code',
     'redirect_uris' => ['http://localhost/callback', 'http://127.0.0.1/callback'],
     'grant_types' => %w[authorization_code refresh_token], 'response_types' => ['code'],
     'token_endpoint_auth_method' => 'none'}.merge(extra)
  end

  def authorize(client_id = CLIENT_ID, redirect_uri: LOOPBACK)
    get '/oauth/authorize', params: {client_id: client_id, redirect_uri: redirect_uri, response_type: 'code',
      state: 's', code_challenge: @challenge, code_challenge_method: 'S256', scope: 'view_issues add_issues'}
  end

  def test_trusted_document_creates_public_application_and_completes_flow
    CIMD.expects(:fetch).with(CLIENT_ID).once.returns(document)
    log_user('jsmith', 'jsmith')
    authorize
    assert_response :success
    app = Doorkeeper::Application.find_by!(uid: CLIENT_ID)
    assert_equal 'Claude Code', app.name
    assert_not app.confidential?
    assert RedmineMcp::NativeOauth.mcp?(app)
    assert_equal SCOPES.split.sort.join(' '), app.scopes.to_s
    authorize # cached: no second fetch within the refresh window
    assert_response :success
    post '/oauth/authorize', params: {client_id: CLIENT_ID, redirect_uri: LOOPBACK, response_type: 'code', state: 's',
      code_challenge: @challenge, code_challenge_method: 'S256', scope: 'view_issues add_issues'}
    code = query_of(response.location)['code']
    assert code.present?
    post '/oauth/token', params: {grant_type: 'authorization_code', client_id: CLIENT_ID,
      redirect_uri: LOOPBACK, code: code, code_verifier: @verifier}
    assert_response :success
    j = JSON.parse(response.body)
    assert_equal %w[add_issues view_issues], j['scope'].split.sort
    assert_equal 3600, j['expires_in']
    assert j['refresh_token'].present?
  end

  def test_stale_or_rescoped_application_is_refreshed_from_document
    CIMD.stubs(:fetch).returns(document)
    log_user('jsmith', 'jsmith')
    authorize
    app = Doorkeeper::Application.find_by!(uid: CLIENT_ID)
    app.update_columns(updated_at: 2.hours.ago)
    CIMD.stubs(:fetch).returns(document('client_name' => 'Claude Code 2'))
    authorize
    assert_equal 'Claude Code 2', app.reload.name
    mcp_settings('cimd_trusted_hosts' => 'claude.ai', 'scopes' => 'view_issues')
    authorize
    assert_equal 'view_issues', app.reload.scopes.to_s
    assert_equal 1, Doorkeeper::Application.count
  end

  def test_untrusted_host_is_never_fetched
    CIMD.expects(:fetch).never
    log_user('jsmith', 'jsmith')
    authorize('https://evil.example.com/client.json')
    assert_equal 0, Doorkeeper::Application.count
    assert_select 'input[name=commit][value=Authorize]', 0
  end

  def test_candidate_requires_https_default_port_and_path
    assert CIMD.candidate?(CLIENT_ID)
    assert CIMD.candidate?('https://mcp.example.org/client.json')
    ['http://claude.ai/oauth/x', 'https://claude.ai:8443/oauth/x', 'https://claude.ai/', 'https://claude.ai',
     'https://claude.ai.evil.example/x', 'https://example.org/x', 'https://u:p@claude.ai/x',
     'https://claude.ai/x?y=1', 'https://claude.ai/x#f', 'some-uuid'].each do |id|
      assert_not CIMD.candidate?(id), id
    end
  end

  def test_invalid_documents_are_rejected
    log_user('jsmith', 'jsmith')
    [document('client_id' => 'https://claude.ai/other'), document('token_endpoint_auth_method' => 'private_key_jwt'),
     document('redirect_uris' => ['http://evil.example/cb']), document('redirect_uris' => []),
     document('grant_types' => ['client_credentials']), document('response_types' => ['token']), ['not', 'an', 'object']].each do |doc|
      CIMD.stubs(:fetch).returns(doc)
      authorize
      assert_response :bad_request, doc.inspect
      assert_equal 'invalid_client', JSON.parse(response.body)['error']
    end
    assert_equal 0, Doorkeeper::Application.count
  end

  def test_redirect_must_be_listed_in_document
    CIMD.stubs(:fetch).returns(document('redirect_uris' => ['https://claude.ai/api/mcp/auth_callback']))
    log_user('jsmith', 'jsmith')
    authorize
    assert_select 'input[name=commit][value=Authorize]', 0
    authorize(redirect_uri: 'https://claude.ai/api/mcp/auth_callback')
    assert_response :success
  end

  def test_manually_created_application_with_same_uid_is_not_taken_over
    Doorkeeper::Application.create!(uid: CLIENT_ID, name: 'Manual', redirect_uri: 'https://example.com/cb',
                                    scopes: 'view_issues', confidential: true)
    CIMD.expects(:fetch).never
    log_user('jsmith', 'jsmith')
    authorize
    assert_response :bad_request
    assert_equal 'Manual', Doorkeeper::Application.find_by!(uid: CLIENT_ID).name
  end

  def test_fetch_errors_become_invalid_client
    Net::HTTP.stubs(:start).raises(SocketError, 'getaddrinfo')
    log_user('jsmith', 'jsmith')
    authorize
    assert_response :bad_request
    assert_match(/could not be fetched/, JSON.parse(response.body)['error_description'])
  end
end
