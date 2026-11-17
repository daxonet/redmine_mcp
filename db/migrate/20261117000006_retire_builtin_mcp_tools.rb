# frozen_string_literal: true

# 2.0 hands the /mcp endpoint to RedmineUP Agent, which authorises tool calls
# with Redmine permission scopes. Applications that only carry the retired
# 1.x "mcp_tools" scope can no longer do anything, so remove them (and their
# grants and tokens). Users reconnect once and get the new scopes.
class RetireBuiltinMcpTools < ActiveRecord::Migration[7.2]
  def up
    Doorkeeper::Application.reset_column_information
    Doorkeeper::Application.where(scopes: %w[mcp_tools mcp:tools]).find_each(&:destroy!)
  end

  def down
    # Nothing to restore; deleted connections are re-created by reconnecting.
  end
end
