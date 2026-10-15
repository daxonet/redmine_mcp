# Run without a Redmine database, with ActiveSupport available:
# bundle exec ruby plugins/redmine_mcp/test/standalone/tool_authorization_check.rb
require 'minitest/autorun'
require 'ostruct'
require 'active_support/core_ext/object/blank'

class User
  class << self
    attr_accessor :current
  end
end
class Project
  class << self
    attr_accessor :records
    def visible(user)
      ids = user.visible_ids
      Object.new.tap { |scope| scope.define_singleton_method(:exists?) { |id:| ids.include?(id) } }
    end
  end
end
class Version
  class << self
    attr_accessor :records
    def find_by(id:) = records[id]
  end
end
module RedmineMcp
  module Tools
    class << self
      attr_accessor :dispatched
      def find_project(id, user)
        Project.records.values.find { |project| [project.id.to_s, project.identifier].include?(id.to_s) && user.visible_ids.include?(project.id) }
      end
      def call(name, _args, _user)
        raise 'handler failed' if name == 'failure_probe'
        self.dispatched = true
        { name: name, actor: User.current }
      end
    end
  end
end
require_relative '../../lib/redmine_mcp/authorization'

class ToolAuthorizationTest < Minitest::Test
  Actor = Struct.new(:visible_ids, :permissions) do
    def allowed_to?(permission, _project, **_options) = permissions.include?(permission)
  end

  def setup
    @project = OpenStruct.new(id: 10, identifier: 'private-test')
    Project.records = { 10 => @project }
    Version.records = { 20 => OpenStruct.new(project: @project) }
    @reader = Actor.new([10], [])
    @manager = Actor.new([10], [:manage_versions, :edit_project, :add_project])
    @outsider = Actor.new([], [:manage_versions])
    @previous = Object.new
    User.current = @previous
    RedmineMcp::Tools.dispatched = false
  end

  def teardown
    User.current = nil
  end

  def test_read_permission_never_grants_version_write_permission
    error = assert_raises(RuntimeError) { RedmineMcp::Tools.call('update_version', { 'id' => 20 }, @reader) }
    assert_match(/Not authorized/, error.message)
    refute RedmineMcp::Tools.dispatched
    assert_same @previous, User.current
  end

  def test_a_known_id_does_not_make_a_private_record_visible
    error = assert_raises(RuntimeError) { RedmineMcp::Tools.call('delete_version', { 'id' => 20 }, @outsider) }
    assert_equal 'Project not found or not authorized', error.message
    refute RedmineMcp::Tools.dispatched
  end

  def test_missing_and_hidden_records_have_the_same_error
    missing = assert_raises(RuntimeError) { RedmineMcp::Tools.call('get_version', { 'id' => 999 }, @reader) }
    hidden = assert_raises(RuntimeError) { RedmineMcp::Tools.call('get_version', { 'id' => 20 }, @outsider) }
    assert_equal missing.message, hidden.message
  end

  def test_allowed_handlers_run_as_the_token_user_and_restore_the_previous_user
    result = RedmineMcp::Tools.call('update_version', { 'id' => 20 }, @manager)
    assert RedmineMcp::Tools.dispatched
    assert_same @manager, result[:actor]
    assert_same @previous, User.current
  end

  def test_handler_errors_do_not_leak_user_identity_to_the_next_request
    assert_raises(RuntimeError) { RedmineMcp::Tools.call('failure_probe', {}, @manager) }
    assert_same @previous, User.current
  end

  def test_project_creation_requires_its_own_global_permission
    assert_raises(RuntimeError) { RedmineMcp::Tools.call('create_project', {}, @reader) }
    refute RedmineMcp::Tools.dispatched
    assert RedmineMcp::Tools.call('create_project', {}, @manager)
  end

  def test_visible_projects_still_require_the_specific_maintenance_permission
    assert_raises(RuntimeError) { RedmineMcp::Tools.authorize_tool!('create_membership', { 'project_id' => 'private-test' }, @reader) }
    refute RedmineMcp::Tools.dispatched
  end
end
