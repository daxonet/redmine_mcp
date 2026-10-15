# frozen_string_literal: true

# Old bookmarks continue to work; administration now uses Redmine Applications.
class McpAdminController < ApplicationController
  before_action :require_admin

  def index
    redirect_to oauth_applications_path
  end
end
