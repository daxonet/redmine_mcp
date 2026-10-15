module RedmineMcp
  # The OAuth token identifies a user; it never grants a Redmine permission.
  # Keep project-owned tools behind the same project permissions as the UI.
  module Authorization
    PROJECT_PERMISSIONS = {
      'update_project' => :edit_project,
      'list_issue_categories' => :view_issues,
      'create_issue_category' => :manage_categories,
      'list_versions' => :view_issues,
      'create_version' => :manage_versions,
      'list_wiki_pages' => :view_wiki_pages,
      'get_wiki_page' => :view_wiki_pages,
      'create_update_wiki_page' => :edit_wiki_pages,
      'delete_wiki_page' => :delete_wiki_pages,
      'list_memberships' => :view_members,
      'create_membership' => :manage_members
    }.freeze
    RECORD_PERMISSIONS = {
      'update_issue_category' => ['IssueCategory', :manage_categories],
      'delete_issue_category' => ['IssueCategory', :manage_categories],
      'get_version' => ['Version', :view_issues],
      'update_version' => ['Version', :manage_versions],
      'delete_version' => ['Version', :manage_versions],
      'update_membership' => ['Member', :manage_members],
      'delete_membership' => ['Member', :manage_members]
    }.freeze

    def call(name, args, user)
      previous_user = User.current
      User.current = user
      authorize_tool!(name, args, user)
      super
    ensure
      User.current = previous_user
    end

    def authorize_tool!(name, args, user)
      if name == 'create_project'
        raise 'Not authorized to create projects' unless user.allowed_to?(:add_project, nil, global: true)
      elsif PROJECT_PERMISSIONS.key?(name)
        key = name == 'update_project' ? 'id' : 'project_id'
        project = find_project(args[key], user)
        authorize_project!(project, PROJECT_PERMISSIONS[name], user)
        if name == 'create_update_wiki_page'
          page = project.wiki&.find_page(Wiki.titleize(args['title']))
          raise 'Not authorized to edit this wiki page' if page && !page.editable_by?(user)
        end
      elsif RECORD_PERMISSIONS.key?(name)
        model, permission = RECORD_PERMISSIONS[name]
        record = Object.const_get(model).find_by(id: args['id'].to_i)
        authorize_project!(record&.project, permission, user)
      elsif %w[update_time_entry delete_time_entry].include?(name)
        entry = TimeEntry.visible(user).find_by(id: args['id'].to_i)
        raise 'Not authorized to modify this time entry' unless entry && entry.editable_by?(user)
      elsif name == 'create_time_entry'
        project = args['project_id'].present? ? find_project(args['project_id'], user) : nil
        if args['issue_id'].present?
          issue = Issue.visible(user).find_by(id: args['issue_id'].to_i)
          raise 'Issue not found' unless issue
          raise 'Issue does not belong to the requested project' if project && issue.project_id != project.id
          project ||= issue.project
        end
        authorize_project!(project, :log_time, user)
      end
    end

    def authorize_project!(project, permission, user)
      # Use the same generic error for hidden and nonexistent objects.
      raise 'Project not found or not authorized' unless project && Project.visible(user).exists?(id: project.id)
      if permission && !user.allowed_to?(permission, project)
        raise "Not authorized: #{permission}"
      end
    end

    def update_project(args, user)
      project = find_project(args['id'], user)
      authorize_project!(project, :edit_project, user)
      project.public_send(:safe_attributes=, args.slice('name', 'description', 'is_public', 'parent_id', 'tracker_ids'), user)
      raise "Failed to update project: #{project.errors.full_messages.join(', ')}" unless project.save
      serialize_project(project, detailed: true)
    end

    def create_issue(args, user)
      Issue.transaction do
        project = find_project(args['project_id'], user)
        authorize_project!(project, :add_issues, user)
        issue = Issue.new(project: project, author: user)
        attrs = args.slice('subject', 'description', 'tracker_id', 'status_id', 'priority_id',
                           'assigned_to_id', 'category_id', 'fixed_version_id', 'parent_issue_id',
                           'start_date', 'due_date', 'estimated_hours', 'done_ratio').reject { |_, value| value.nil? }
        attrs['tracker_id'] ||= project.trackers.first&.id
        attrs['custom_field_values'] = custom_field_values_for(args) if args['custom_fields'].present?
        issue.public_send(:safe_attributes=, attrs, user)
        if issue.tracker_id != attrs['tracker_id'].to_i
          raise 'Not authorized to create issues with this tracker'
        end
        if attrs['status_id'] && issue.status_id != attrs['status_id'].to_i
          raise 'Not authorized to use this initial status'
        end
        raise "Failed to create issue: #{issue.errors.full_messages.join(', ')}" unless issue.save
        attach_uploads(issue, args['uploads'], user) if args['uploads'].present?
        serialize_issue(issue.reload)
      end
    end

    def update_issue(args, user)
      Issue.transaction do
        issue = Issue.visible(user).find_by(id: args['id'].to_i)
        raise 'Issue not found' unless issue
        attrs = args.slice('subject', 'description', 'status_id', 'priority_id', 'assigned_to_id',
                           'category_id', 'fixed_version_id', 'parent_issue_id', 'done_ratio',
                           'due_date', 'start_date', 'estimated_hours').reject { |_, value| value.nil? }
        attrs['custom_field_values'] = custom_field_values_for(args) if args['custom_fields'].present?
        if attrs.any? && !issue.attributes_editable?(user)
          raise 'Not authorized to edit this issue'
        end
        if args['notes'].present? && !issue.notes_addable?(user)
          raise 'Not authorized to add issue notes'
        end
        if args['uploads'].present? && !issue.attachments_addable?(user)
          raise 'Not authorized to add attachments'
        end
        issue.init_journal(user, args['notes'])
        reason = args['reason'].presence || args['notes'].presence
        issue.update_reason = reason if issue.respond_to?(:update_reason=)
        issue.current_journal.reason = reason if issue.current_journal.respond_to?(:reason=)
        issue.public_send(:safe_attributes=, attrs, user)
        if attrs['status_id'] && issue.status_id != attrs['status_id'].to_i
          raise 'Not authorized by the issue workflow'
        end
        raise "Failed to update issue: #{issue.errors.full_messages.join(', ')}" unless issue.save
        attach_uploads(issue, args['uploads'], user) if args['uploads'].present?
        serialize_issue(issue.reload)
      end
    end

    def custom_field_values_for(args)
      args['custom_fields'].each_with_object({}) { |field, values| values[field['id'].to_s] = field['value'] }
    end
  end
end

RedmineMcp::Tools.singleton_class.prepend(RedmineMcp::Authorization) unless
  RedmineMcp::Tools.singleton_class.ancestors.include?(RedmineMcp::Authorization)
