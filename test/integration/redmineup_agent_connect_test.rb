# frozen_string_literal: true
require File.expand_path('../../test_helper', __FILE__)

# End-to-end against the real RedmineUP Agent MCP server. Skipped where the
# commercial plugin is not installed (e.g. public CI).
class RedmineupAgentConnectTest < Redmine::IntegrationTest
  include McpTestSetup
  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles, :issues,
           :issue_statuses, :trackers, :projects_trackers, :enabled_modules, :enumerations

  def setup
    skip 'RedmineUP Agent is not installed' unless Redmine::Plugin.installed?(:redmineup_agent)
    super
    Setting.rest_api_enabled = '1'
    Setting.host_name = 'www.example.com'
    Setting.plugin_redmineup_agent = Setting.plugin_redmineup_agent.to_h.merge('mcp_enabled' => '1')
    mcp_settings('scopes' => '', 'allowed_redirect_uris' => "http://localhost:*/callback\n#{CALLBACK}")
    reset_oauth_tables
    @verifier, @challenge = pkce
  end

  def mcp(body, token: nil)
    headers = {'Content-Type' => 'application/json', 'Accept' => 'application/json, text/event-stream'}
    headers['Authorization'] = "Bearer #{token}" if token
    post '/mcp', params: body.to_json, headers: headers
  end

  def test_our_discovery_wins_and_advertises_redmineup_scopes
    mcp({jsonrpc: '2.0', id: 1, method: 'ping'})
    assert_response :unauthorized
    assert_match %r{resource_metadata="http://www.example.com/.well-known/oauth-protected-resource/mcp"},
                 response.headers['WWW-Authenticate']
    get '/.well-known/oauth-protected-resource/mcp'
    scopes = JSON.parse(response.body)['scopes_supported']
    assert_includes scopes, 'view_issues'
    assert_not_includes scopes, 'admin'
    assert_equal RedmineMcp::Backend.scopes.sort, scopes.sort
    get '/.well-known/oauth-authorization-server'
    assert JSON.parse(response.body)['registration_endpoint'].end_with?('/mcp/oauth/register')
  end

  def test_dynamic_registration_to_redmineup_tools
    redirect = 'http://localhost:43123/callback'
    post '/mcp/oauth/register', params: {client_name: 'Claude Code', redirect_uris: [redirect],
                                          token_endpoint_auth_method: 'none'}.to_json,
                                headers: {'Content-Type' => 'application/json'}
    assert_response :created, response.body
    registration = JSON.parse(response.body)
    client_id = registration['client_id']
    log_user('jsmith', 'jsmith')
    params = {client_id: client_id, redirect_uri: redirect, response_type: 'code', state: 's',
              code_challenge: @challenge, code_challenge_method: 'S256', resource: 'http://www.example.com/mcp',
              scope: registration['scope']}
    get '/oauth/authorize', params: params
    assert_response :success
    post '/oauth/authorize', params: params
    code = query_of(response.location)['code']
    reset!
    post '/oauth/token', params: {grant_type: 'authorization_code', client_id: client_id, redirect_uri: redirect,
                                  code: code, code_verifier: @verifier, resource: 'http://www.example.com/mcp'}
    assert_response :success
    token = JSON.parse(response.body)['access_token']

    mcp({jsonrpc: '2.0', id: 1, method: 'initialize',
         params: {protocolVersion: '2025-03-26', capabilities: {}, clientInfo: {name: 'test', version: '1'}}}, token: token)
    assert_response :success
    assert JSON.parse(response.body).dig('result', 'serverInfo').present?
    mcp({jsonrpc: '2.0', id: 2, method: 'tools/list'}, token: token)
    assert_response :success
    names = JSON.parse(response.body).dig('result', 'tools').map { |t| t['name'] }
    assert_includes names, 'list_issues'
    assert_not_includes names, 'delete_user'
    mcp({jsonrpc: '2.0', id: 3, method: 'tools/call', params: {name: 'get_current_user', arguments: {}}}, token: token)
    assert_response :success
    assert_includes response.body, 'jsmith'
  end
end
