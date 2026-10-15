# frozen_string_literal: true

# CI installs the plugin through a symlink to a separate checkout. __dir__
# therefore is not necessarily below REDMINE_ROOT/plugins.
redmine_root = ENV['REDMINE_HOME'] ||
               (defined?(Rails) && Rails.respond_to?(:root) && Rails.root) ||
               File.expand_path('../../..', __dir__)
require File.join(redmine_root.to_s, 'test', 'test_helper')
