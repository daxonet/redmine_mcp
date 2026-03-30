require 'securerandom'

class McpController < ApplicationController
  include ActionController::Live

  skip_before_action :verify_authenticity_token
  skip_before_action :check_if_login_required, raise: false
  skip_before_action :require_login, raise: false

  # Thread-safe in-memory session store: session_id => { user_id: }
  SESSIONS      = {}
  SESSIONS_LOCK = Mutex.new

  def self.set_session(id, data)    = SESSIONS_LOCK.synchronize { SESSIONS[id] = data }
  def self.get_session(id)          = SESSIONS_LOCK.synchronize { SESSIONS[id] }
  def self.delete_session(id)       = SESSIONS_LOCK.synchronize { SESSIONS.delete(id) }

  # Single entry point for GET / POST / DELETE / OPTIONS
  def handle
    set_cors_headers
    case request.method.upcase
    when 'OPTIONS' then head :ok
    when 'GET'     then head :method_not_allowed  # no server-push needed
    when 'DELETE'  then handle_delete
    when 'POST'    then handle_post
    else                head :method_not_allowed
    end
  end

  private

  # ── Auth ────────────────────────────────────────────────────────────────────

  def authenticate!
    raw = request.headers['Authorization'].to_s
    unless raw.start_with?('Bearer ')
      render_www_authenticate and return nil
    end
    token_str = raw[7..]
    mcp_token = McpOauthToken.find_by_access_token(token_str)
    unless mcp_token
      render_www_authenticate and return nil
    end
    user = User.find_by(id: mcp_token.user_id)
    unless user&.active?
      render_www_authenticate and return nil
    end
    user
  end

  def render_www_authenticate
    base = "#{request.scheme}://#{request.host_with_port}"
    response.set_header(
      'WWW-Authenticate',
      "Bearer resource_metadata=\"#{base}/.well-known/oauth-protected-resource/mcp\""
    )
    render json: { error: 'unauthorized' }, status: :unauthorized
  end

  # ── HTTP method handlers ─────────────────────────────────────────────────────

  def handle_delete
    sid = request.headers['Mcp-Session-Id']
    McpController.delete_session(sid) if sid
    head :ok
  end

  def handle_post
    user = authenticate!
    return unless user

    body = request.body.read
    message = JSON.parse(body)

    # Notification (no id) → 202, no body
    if message['id'].nil?
      handle_notification(message['method'])
      return
    end

    # Request → dispatch and respond
    result = dispatch_request(message, user)

    response.set_header('Content-Type', 'application/json')
    render json: result
  rescue JSON::ParserError
    render json: jsonrpc_error(nil, -32_700, 'Parse error'), status: :bad_request
  rescue => e
    Rails.logger.error "[MCP] Unhandled error: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}"
    render json: jsonrpc_error(nil, -32_603, 'Internal error') unless response.committed?
  end

  def handle_notification(method)
    case method
    when 'notifications/initialized'
      # nothing to do
    end
    head :accepted
  end

  # ── JSON-RPC dispatch ────────────────────────────────────────────────────────

  def dispatch_request(msg, user)
    id     = msg['id']
    method = msg['method']
    params = msg['params'] || {}

    case method
    when 'initialize'
      handle_initialize(id, params, user)

    when 'tools/list'
      jsonrpc_result(id, { tools: RedmineMcp::Tools.definitions })

    when 'tools/call'
      handle_tools_call(id, params, user)

    when 'ping'
      jsonrpc_result(id, {})

    else
      jsonrpc_error(id, -32_601, "Method not found: #{method}")
    end
  end

  def handle_initialize(id, _params, user)
    sid = SecureRandom.uuid
    McpController.set_session(sid, { user_id: user.id })
    response.set_header('Mcp-Session-Id', sid)

    jsonrpc_result(id, {
      protocolVersion: '2025-03-26',
      capabilities:    { tools: { listChanged: false } },
      serverInfo:      { name: 'redmine-mcp', version: '1.0.0' }
    })
  end

  def handle_tools_call(id, params, user)
    tool_name = params['name']
    arguments = params['arguments'] || {}

    # Validate session when provided
    if (sid = request.headers['Mcp-Session-Id'])
      unless McpController.get_session(sid)
        return jsonrpc_error(id, -32_001, 'Session not found')
      end
    end

    result_data = RedmineMcp::Tools.call(tool_name, arguments, user)
    jsonrpc_result(id, {
      content: [{ type: 'text', text: result_data.to_json }]
    })
  rescue => e
    jsonrpc_result(id, {
      content: [{ type: 'text', text: e.message }],
      isError: true
    })
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  def jsonrpc_result(id, result)
    { jsonrpc: '2.0', id: id, result: result }
  end

  def jsonrpc_error(id, code, message)
    { jsonrpc: '2.0', id: id, error: { code: code, message: message } }
  end

  def set_cors_headers
    response.set_header('Access-Control-Allow-Origin',   '*')
    response.set_header('Access-Control-Allow-Methods',  'GET, POST, DELETE, OPTIONS')
    response.set_header('Access-Control-Allow-Headers',  'Content-Type, Authorization, Mcp-Session-Id, Accept')
    response.set_header('Access-Control-Expose-Headers', 'Mcp-Session-Id')
  end
end
