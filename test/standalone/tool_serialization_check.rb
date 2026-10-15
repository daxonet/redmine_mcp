require 'minitest/autorun'
require 'ostruct'
require 'active_support/core_ext/object/blank'
require_relative '../../lib/redmine_mcp/tools'

class Attachment
  class << self
    attr_accessor :result
    def attach_files(*) = result
  end
end

class ToolSerializationTest < Minitest::Test
  def test_membership_uses_redmine_user_foreign_key
    member = OpenStruct.new(id: 2, user_id: 7, principal: OpenStruct.new(name: 'Test user'), roles: [], project_id: 3)
    assert_equal 7, RedmineMcp::Tools.serialize_membership(member)[:principal][:id]
  end

  def test_valid_upload_result_is_saved
    container = Object.new
    container.define_singleton_method(:save!) { @saved = true }
    Attachment.result = { files: [Object.new], unsaved: [] }
    RedmineMcp::Tools.attach_uploads(container, [{'token' => 'valid'}], nil)
    assert container.instance_variable_get(:@saved)
  end

  def test_missing_token_cannot_report_success
    Attachment.result = { files: [], unsaved: [] }
    assert_raises(RuntimeError) do
      RedmineMcp::Tools.attach_uploads(Object.new, [{'token' => 'missing'}], nil)
    end
  end

  def test_partial_or_invalid_upload_cannot_report_success
    [{ files: [Object.new], unsaved: [] }, { files: [Object.new], unsaved: [Object.new] }].each do |result|
      Attachment.result = result
      assert_raises(RuntimeError) do
        RedmineMcp::Tools.attach_uploads(Object.new, [{'token' => 'a'}, {'token' => 'b'}], nil)
      end
    end
  end
end
