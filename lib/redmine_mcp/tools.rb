module RedmineMcp
  module Tools
    # ── Tool definitions (MCP schema) ─────────────────────────────────────────

    def self.definitions
      [
        {
          name: 'list_projects',
          description: 'List all Redmine projects accessible to the current user',
          inputSchema: {
            type: 'object',
            properties: {
              limit:  { type: 'integer', description: 'Max results (default 25)' },
              offset: { type: 'integer', description: 'Offset for pagination' }
            }
          }
        },
        {
          name: 'get_project',
          description: 'Get details of a project by identifier or numeric ID',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'string', description: 'Project identifier (slug) or numeric ID' }
            }
          }
        },
        {
          name: 'list_issues',
          description: 'List and filter issues',
          inputSchema: {
            type: 'object',
            properties: {
              project_id:     { type: 'string',  description: 'Filter by project identifier' },
              tracker_id:     { type: 'integer', description: 'Filter by tracker ID' },
              status_id:      { type: 'string',  description: '"open" | "closed" | "*" | numeric ID (default: open)' },
              assigned_to_id: { type: 'string',  description: 'Assignee user ID or "me"' },
              limit:          { type: 'integer', description: 'Max results (default 25)' },
              offset:         { type: 'integer', description: 'Offset for pagination' },
              sort:           { type: 'string',  description: 'Sort field, e.g. "updated_on:desc"' }
            }
          }
        },
        {
          name: 'get_issue',
          description: 'Get full details of an issue including journals (comments)',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Issue ID' }
            }
          }
        },
        {
          name: 'create_issue',
          description: 'Create a new issue in a Redmine project',
          inputSchema: {
            type: 'object',
            required: %w[project_id subject],
            properties: {
              project_id:      { type: 'string',  description: 'Project identifier (required)' },
              subject:         { type: 'string',  description: 'Issue title (required)' },
              description:     { type: 'string',  description: 'Issue description' },
              tracker_id:      { type: 'integer', description: 'Tracker ID' },
              status_id:       { type: 'integer', description: 'Status ID' },
              priority_id:     { type: 'integer', description: 'Priority ID' },
              assigned_to_id:  { type: 'integer', description: 'Assignee user ID' },
              start_date:      { type: 'string',  description: 'Start date (YYYY-MM-DD)' },
              due_date:        { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              estimated_hours: { type: 'number',  description: 'Estimated hours' }
            }
          }
        },
        {
          name: 'update_issue',
          description: 'Update an existing issue (can also add a comment via notes)',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:              { type: 'integer', description: 'Issue ID (required)' },
              subject:         { type: 'string',  description: 'New subject' },
              description:     { type: 'string',  description: 'New description' },
              status_id:       { type: 'integer', description: 'New status ID' },
              priority_id:     { type: 'integer', description: 'New priority ID' },
              assigned_to_id:  { type: 'integer', description: 'New assignee user ID' },
              notes:           { type: 'string',  description: 'Comment to add' },
              done_ratio:      { type: 'integer', description: 'Percentage done (0-100)' },
              due_date:        { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              estimated_hours: { type: 'number',  description: 'Estimated hours' }
            }
          }
        },
        {
          name: 'list_users',
          description: 'List Redmine users (requires admin privileges)',
          inputSchema: {
            type: 'object',
            properties: {
              limit:  { type: 'integer', description: 'Max results' },
              offset: { type: 'integer', description: 'Offset' }
            }
          }
        },
        {
          name: 'search',
          description: 'Search issues and projects by keyword',
          inputSchema: {
            type: 'object',
            required: ['query'],
            properties: {
              query:  { type: 'string',  description: 'Search keyword (required)' },
              limit:  { type: 'integer', description: 'Max results (default 25)' }
            }
          }
        },
        {
          name: 'list_time_entries',
          description: 'List time entries with optional filters',
          inputSchema: {
            type: 'object',
            properties: {
              project_id: { type: 'string',  description: 'Filter by project identifier' },
              issue_id:   { type: 'integer', description: 'Filter by issue ID' },
              user_id:    { type: 'integer', description: 'Filter by user ID' },
              from:       { type: 'string',  description: 'From date (YYYY-MM-DD)' },
              to:         { type: 'string',  description: 'To date (YYYY-MM-DD)' },
              limit:      { type: 'integer', description: 'Max results' },
              offset:     { type: 'integer', description: 'Offset' }
            }
          }
        },
        {
          name: 'create_time_entry',
          description: 'Log time on an issue or project',
          inputSchema: {
            type: 'object',
            required: %w[hours activity_id],
            properties: {
              issue_id:   { type: 'integer', description: 'Issue ID (or project_id required)' },
              project_id: { type: 'string',  description: 'Project identifier (or issue_id required)' },
              hours:      { type: 'number',  description: 'Hours spent (required)' },
              activity_id:{ type: 'integer', description: 'Activity type ID (required)' },
              comments:   { type: 'string',  description: 'Comments' },
              spent_on:   { type: 'string',  description: 'Date (YYYY-MM-DD, default today)' }
            }
          }
        }
      ]
    end

    # ── Tool dispatch ──────────────────────────────────────────────────────────

    def self.call(name, args, user)
      case name
      when 'list_projects'     then list_projects(args, user)
      when 'get_project'       then get_project(args, user)
      when 'list_issues'       then list_issues(args, user)
      when 'get_issue'         then get_issue(args, user)
      when 'create_issue'      then create_issue(args, user)
      when 'update_issue'      then update_issue(args, user)
      when 'list_users'        then list_users(args, user)
      when 'search'            then search(args, user)
      when 'list_time_entries' then list_time_entries(args, user)
      when 'create_time_entry' then create_time_entry(args, user)
      else raise "Unknown tool: #{name}"
      end
    end

    # ── Implementations (direct ActiveRecord access) ───────────────────────────

    def self.list_projects(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i

      scope = Project.visible(user)
      total = scope.count
      items = scope.order(:name).offset(offset).limit(limit)

      {
        projects:    items.map { |p| serialize_project(p) },
        total_count: total,
        offset:      offset,
        limit:       limit
      }
    end

    def self.get_project(args, user)
      id = args['id'].to_s
      project = if id.match?(/\A\d+\z/)
                  Project.visible(user).find_by(id: id.to_i)
                else
                  Project.visible(user).find_by(identifier: id)
                end
      raise "Project not found: #{id}" unless project

      serialize_project(project, detailed: true)
    end

    def self.list_issues(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i

      scope = Issue.visible(user).includes(:status, :tracker, :priority, :assigned_to)

      if args['project_id']
        project = Project.visible(user).find_by(identifier: args['project_id']) ||
                  Project.visible(user).find_by(id: args['project_id'].to_i)
        scope = scope.where(project_id: project.id) if project
      end

      scope = scope.where(tracker_id: args['tracker_id'].to_i) if args['tracker_id']

      case args['status_id'].to_s
      when 'open', ''
        scope = scope.open
      when 'closed'
        scope = scope.where(status: IssueStatus.where(is_closed: true))
      when '*'
        # no filter
      else
        scope = scope.where(status_id: args['status_id'].to_i)
      end

      if args['assigned_to_id'].to_s == 'me'
        scope = scope.where(assigned_to_id: user.id)
      elsif args['assigned_to_id']
        scope = scope.where(assigned_to_id: args['assigned_to_id'].to_i)
      end

      # Sort
      sort_field, sort_dir = (args['sort'] || 'id:desc').split(':')
      sort_dir = %w[asc desc].include?(sort_dir) ? sort_dir : 'asc'
      scope = scope.order(Arel.sql("issues.#{sort_field} #{sort_dir}")) rescue scope.order('issues.id desc')

      total = scope.count
      items = scope.offset(offset).limit(limit)

      {
        issues:      items.map { |i| serialize_issue_brief(i) },
        total_count: total,
        offset:      offset,
        limit:       limit
      }
    end

    def self.get_issue(args, user)
      issue = Issue.visible(user)
                   .includes(:status, :tracker, :priority, :assigned_to,
                             :author, journals: :user)
                   .find_by(id: args['id'].to_i)
      raise "Issue ##{args['id']} not found" unless issue

      serialize_issue(issue)
    end

    def self.create_issue(args, user)
      project = Project.visible(user).find_by(identifier: args['project_id']) ||
                Project.visible(user).find_by(id: args['project_id'].to_i)
      raise "Project not found: #{args['project_id']}" unless project

      issue = Issue.new(
        project:         project,
        author:          user,
        subject:         args['subject'],
        description:     args['description'],
        tracker_id:      args['tracker_id'] || project.trackers.first&.id,
        status_id:       args['status_id']  || IssueStatus.where(is_closed: false).order(:position).first&.id,
        priority_id:     args['priority_id'] || IssuePriority.default&.id,
        assigned_to_id:  args['assigned_to_id'],
        start_date:      args['start_date'],
        due_date:        args['due_date'],
        estimated_hours: args['estimated_hours']
      )

      raise "Failed to create issue: #{issue.errors.full_messages.join(', ')}" unless issue.save

      serialize_issue(issue)
    end

    def self.update_issue(args, user)
      issue = Issue.visible(user).find_by(id: args['id'].to_i)
      raise "Issue ##{args['id']} not found" unless issue

      issue.init_journal(user, args['notes']) if args['notes'].present?

      updatable = %w[subject description status_id priority_id assigned_to_id
                     done_ratio due_date start_date estimated_hours]
      attrs = args.slice(*updatable).reject { |_, v| v.nil? }
      issue.assign_attributes(attrs) unless attrs.empty?

      raise "Failed to update issue: #{issue.errors.full_messages.join(', ')}" unless issue.save

      serialize_issue(issue.reload)
    end

    def self.list_users(args, user)
      raise 'Admin privileges required to list users' unless user.admin?

      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i

      scope = User.active.where.not(type: 'AnonymousUser')
      total = scope.count
      items = scope.order(:login).offset(offset).limit(limit)

      {
        users:       items.map { |u| serialize_user(u) },
        total_count: total,
        offset:      offset,
        limit:       limit
      }
    end

    def self.search(args, user)
      q     = args['query'].to_s.strip
      limit = (args['limit'] || 25).to_i.clamp(1, 100)
      raise 'Search query required' if q.blank?

      pattern = "%#{q}%"

      issues = Issue.visible(user)
                    .where('issues.subject LIKE ? OR issues.description LIKE ?', pattern, pattern)
                    .includes(:project, :status)
                    .limit(limit)

      projects = Project.visible(user)
                        .where('projects.name LIKE ? OR projects.description LIKE ?', pattern, pattern)
                        .limit(10)

      results = []
      results += projects.map do |p|
        { type: 'project', id: p.id, title: p.name,
          url: "/projects/#{p.identifier}" }
      end
      results += issues.map do |i|
        { type: 'issue', id: i.id, title: i.subject,
          project: i.project.name, status: i.status.name,
          url: "/issues/#{i.id}" }
      end

      { results: results, total_count: results.size }
    end

    def self.list_time_entries(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i

      scope = TimeEntry.visible(user).includes(:project, :issue, :activity)

      if args['project_id']
        project = Project.visible(user).find_by(identifier: args['project_id'])
        scope = scope.where(project_id: project.id) if project
      end

      scope = scope.where(issue_id:  args['issue_id'].to_i) if args['issue_id']
      scope = scope.where(user_id:   args['user_id'].to_i)  if args['user_id']
      scope = scope.where('spent_on >= ?', args['from'])     if args['from']
      scope = scope.where('spent_on <= ?', args['to'])       if args['to']

      total = scope.count
      items = scope.order(spent_on: :desc).offset(offset).limit(limit)

      {
        time_entries: items.map { |t| serialize_time_entry(t) },
        total_count:  total,
        offset:       offset,
        limit:        limit
      }
    end

    def self.create_time_entry(args, user)
      project_id = nil
      if args['project_id']
        project = Project.visible(user).find_by(identifier: args['project_id'])
        project_id = project&.id
      end

      entry = TimeEntry.new(
        project_id:  project_id,
        issue_id:    args['issue_id'],
        user:        user,
        hours:       args['hours'],
        activity_id: args['activity_id'],
        comments:    args['comments'],
        spent_on:    args['spent_on'] || Date.today
      )

      # Infer project from issue if not supplied
      if entry.project_id.nil? && entry.issue_id
        entry.project_id = Issue.find_by(id: entry.issue_id)&.project_id
      end

      raise "Failed to log time: #{entry.errors.full_messages.join(', ')}" unless entry.save

      serialize_time_entry(entry)
    end

    # ── Serializers ────────────────────────────────────────────────────────────

    def self.serialize_project(p, detailed: false)
      h = {
        id:          p.id,
        name:        p.name,
        identifier:  p.identifier,
        description: p.description.to_s.truncate(500),
        status:      p.status,
        is_public:   p.is_public,
        created_on:  p.created_on&.iso8601,
        updated_on:  p.updated_on&.iso8601,
        parent:      p.parent ? { id: p.parent.id, name: p.parent.name } : nil
      }
      if detailed
        h[:trackers]         = p.trackers.map { |t| { id: t.id, name: t.name } }
        h[:issue_categories] = p.issue_categories.map { |c| { id: c.id, name: c.name } }
      end
      h
    end

    def self.serialize_issue_brief(i)
      {
        id:          i.id,
        subject:     i.subject,
        project:     { id: i.project_id, name: i.project&.name },
        tracker:     { id: i.tracker_id, name: i.tracker&.name },
        status:      { id: i.status_id,  name: i.status&.name  },
        priority:    { id: i.priority_id, name: i.priority&.name },
        assigned_to: i.assigned_to ? { id: i.assigned_to.id, name: i.assigned_to.name } : nil,
        done_ratio:  i.done_ratio,
        created_on:  i.created_on&.iso8601,
        updated_on:  i.updated_on&.iso8601
      }
    end

    def self.serialize_issue(i)
      h = serialize_issue_brief(i)
      h.merge!(
        description:     i.description.to_s,
        author:          { id: i.author_id, name: i.author&.name },
        start_date:      i.start_date&.iso8601,
        due_date:        i.due_date&.iso8601,
        estimated_hours: i.estimated_hours,
        spent_hours:     i.spent_hours,
        closed_on:       i.closed_on&.iso8601
      )
      if i.association(:journals).loaded?
        h[:journals] = i.journals.map do |j|
          {
            id:         j.id,
            user:       { id: j.user_id, name: j.user&.name },
            notes:      j.notes,
            created_on: j.created_on&.iso8601,
            details:    j.details.map { |d| { property: d.property, name: d.prop_key, old_value: d.old_value, new_value: d.value } }
          }
        end
      end
      h
    end

    def self.serialize_user(u)
      {
        id:         u.id,
        login:      u.login,
        firstname:  u.firstname,
        lastname:   u.lastname,
        name:       u.name,
        mail:       u.mail,
        admin:      u.admin?,
        created_on: u.created_on&.iso8601
      }
    end

    def self.serialize_time_entry(t)
      {
        id:          t.id,
        project:     { id: t.project_id, name: t.project&.name },
        issue:       t.issue_id ? { id: t.issue_id } : nil,
        user:        { id: t.user_id, name: t.user&.name },
        activity:    { id: t.activity_id, name: t.activity&.name },
        hours:       t.hours,
        comments:    t.comments,
        spent_on:    t.spent_on&.iso8601,
        created_on:  t.created_on&.iso8601
      }
    end
  end
end
