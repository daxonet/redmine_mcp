require File.expand_path('../../test_helper', __FILE__)
class McpAdminControllerTest < Redmine::IntegrationTest
  fixtures :users
  def test_bookmark_redirects_admin_to_native_applications
    log_user('admin', 'admin')
    get '/admin/mcp/tokens'
    assert_redirected_to '/oauth/applications'
  end
  def test_nonadmin_cannot_use_admin_bookmark
    log_user('jsmith', 'jsmith')
    get '/admin/mcp/tokens'
    assert_response :forbidden
  end
end
