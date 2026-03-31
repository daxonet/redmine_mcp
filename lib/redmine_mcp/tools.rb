require 'base64'
require 'tempfile'

module RedmineMcp
  module Tools
    # ── Tool definitions (MCP schema) ─────────────────────────────────────────

    def self.definitions
      [
        # ── Projects ──────────────────────────────────────────────────────────
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
          name: 'create_project',
          description: 'Create a new Redmine project (requires admin or appropriate permissions)',
          inputSchema: {
            type: 'object',
            required: %w[name identifier],
            properties: {
              name:        { type: 'string',  description: 'Project name (required)' },
              identifier:  { type: 'string',  description: 'Project identifier/slug (required)' },
              description: { type: 'string',  description: 'Project description' },
              is_public:   { type: 'boolean', description: 'Public project (default true)' },
              parent_id:   { type: 'integer', description: 'Parent project ID' },
              tracker_ids: { type: 'array', items: { type: 'integer' }, description: 'Tracker IDs to enable' }
            }
          }
        },
        {
          name: 'update_project',
          description: 'Update an existing project',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:          { type: 'string',  description: 'Project identifier or numeric ID (required)' },
              name:        { type: 'string',  description: 'New project name' },
              description: { type: 'string',  description: 'New description' },
              is_public:   { type: 'boolean', description: 'Public project' },
              parent_id:   { type: 'integer', description: 'Parent project ID' },
              tracker_ids: { type: 'array', items: { type: 'integer' }, description: 'Tracker IDs to enable' }
            }
          }
        },
        {
          name: 'delete_project',
          description: 'Delete a project and all its data (irreversible, requires admin)',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'string', description: 'Project identifier or numeric ID (required)' }
            }
          }
        },

        # ── Issues ────────────────────────────────────────────────────────────
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
              category_id:    { type: 'integer', description: 'Filter by category ID' },
              version_id:     { type: 'integer', description: 'Filter by version/milestone ID' },
              priority_id:    { type: 'integer', description: 'Filter by priority ID' },
              author_id:      { type: 'integer', description: 'Filter by author user ID' },
              created_on:     { type: 'string',  description: 'Filter by creation date range, e.g. ">=2024-01-01"' },
              updated_on:     { type: 'string',  description: 'Filter by update date range' },
              limit:          { type: 'integer', description: 'Max results (default 25)' },
              offset:         { type: 'integer', description: 'Offset for pagination' },
              sort:           { type: 'string',  description: 'Sort field, e.g. "updated_on:desc"' }
            }
          }
        },
        {
          name: 'get_issue',
          description: 'Get full details of an issue including journals (comments) and attachments',
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
              category_id:     { type: 'integer', description: 'Issue category ID' },
              fixed_version_id:{ type: 'integer', description: 'Target version ID' },
              parent_issue_id: { type: 'integer', description: 'Parent issue ID' },
              start_date:      { type: 'string',  description: 'Start date (YYYY-MM-DD)' },
              due_date:        { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              estimated_hours: { type: 'number',  description: 'Estimated hours' },
              done_ratio:      { type: 'integer', description: 'Percentage done (0-100)' },
              uploads: {
                type: 'array',
                description: 'Attachments to add (use tokens from upload_file)',
                items: {
                  type: 'object',
                  required: ['token'],
                  properties: {
                    token:       { type: 'string', description: 'Upload token from upload_file' },
                    filename:    { type: 'string', description: 'File name' },
                    description: { type: 'string', description: 'Attachment description' }
                  }
                }
              }
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
              id:               { type: 'integer', description: 'Issue ID (required)' },
              subject:          { type: 'string',  description: 'New subject' },
              description:      { type: 'string',  description: 'New description' },
              status_id:        { type: 'integer', description: 'New status ID' },
              priority_id:      { type: 'integer', description: 'New priority ID' },
              assigned_to_id:   { type: 'integer', description: 'New assignee user ID' },
              category_id:      { type: 'integer', description: 'New category ID' },
              fixed_version_id: { type: 'integer', description: 'New target version ID' },
              parent_issue_id:  { type: 'integer', description: 'New parent issue ID' },
              notes:            { type: 'string',  description: 'Comment to add' },
              done_ratio:       { type: 'integer', description: 'Percentage done (0-100)' },
              due_date:         { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              start_date:       { type: 'string',  description: 'Start date (YYYY-MM-DD)' },
              estimated_hours:  { type: 'number',  description: 'Estimated hours' },
              uploads: {
                type: 'array',
                description: 'Attachments to add (use tokens from upload_file)',
                items: {
                  type: 'object',
                  required: ['token'],
                  properties: {
                    token:       { type: 'string', description: 'Upload token from upload_file' },
                    filename:    { type: 'string', description: 'File name' },
                    description: { type: 'string', description: 'Attachment description' }
                  }
                }
              }
            }
          }
        },
        {
          name: 'delete_issue',
          description: 'Delete an issue permanently',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Issue ID (required)' }
            }
          }
        },

        # ── Issue categories ──────────────────────────────────────────────────
        {
          name: 'list_issue_categories',
          description: 'List issue categories for a project',
          inputSchema: {
            type: 'object',
            required: ['project_id'],
            properties: {
              project_id: { type: 'string', description: 'Project identifier or numeric ID (required)' }
            }
          }
        },
        {
          name: 'create_issue_category',
          description: 'Create an issue category in a project',
          inputSchema: {
            type: 'object',
            required: %w[project_id name],
            properties: {
              project_id:      { type: 'string',  description: 'Project identifier (required)' },
              name:            { type: 'string',  description: 'Category name (required)' },
              assigned_to_id:  { type: 'integer', description: 'Default assignee user ID' }
            }
          }
        },
        {
          name: 'update_issue_category',
          description: 'Update an issue category',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:             { type: 'integer', description: 'Category ID (required)' },
              name:           { type: 'string',  description: 'New name' },
              assigned_to_id: { type: 'integer', description: 'Default assignee user ID' }
            }
          }
        },
        {
          name: 'delete_issue_category',
          description: 'Delete an issue category',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Category ID (required)' }
            }
          }
        },

        # ── Versions ──────────────────────────────────────────────────────────
        {
          name: 'list_versions',
          description: 'List versions (milestones) for a project',
          inputSchema: {
            type: 'object',
            required: ['project_id'],
            properties: {
              project_id: { type: 'string', description: 'Project identifier or numeric ID (required)' }
            }
          }
        },
        {
          name: 'get_version',
          description: 'Get details of a version',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Version ID (required)' }
            }
          }
        },
        {
          name: 'create_version',
          description: 'Create a version (milestone) in a project',
          inputSchema: {
            type: 'object',
            required: %w[project_id name],
            properties: {
              project_id:  { type: 'string',  description: 'Project identifier (required)' },
              name:        { type: 'string',  description: 'Version name (required)' },
              description: { type: 'string',  description: 'Description' },
              status:      { type: 'string',  description: '"open" | "locked" | "closed" (default: open)' },
              due_date:    { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              sharing:     { type: 'string',  description: '"none" | "descendants" | "hierarchy" | "tree" | "system"' }
            }
          }
        },
        {
          name: 'update_version',
          description: 'Update a version',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:          { type: 'integer', description: 'Version ID (required)' },
              name:        { type: 'string',  description: 'New name' },
              description: { type: 'string',  description: 'New description' },
              status:      { type: 'string',  description: '"open" | "locked" | "closed"' },
              due_date:    { type: 'string',  description: 'Due date (YYYY-MM-DD)' },
              sharing:     { type: 'string',  description: '"none" | "descendants" | "hierarchy" | "tree" | "system"' }
            }
          }
        },
        {
          name: 'delete_version',
          description: 'Delete a version',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Version ID (required)' }
            }
          }
        },

        # ── Wiki ──────────────────────────────────────────────────────────────
        {
          name: 'list_wiki_pages',
          description: 'List wiki pages for a project',
          inputSchema: {
            type: 'object',
            required: ['project_id'],
            properties: {
              project_id: { type: 'string', description: 'Project identifier or numeric ID (required)' }
            }
          }
        },
        {
          name: 'get_wiki_page',
          description: 'Get content of a wiki page',
          inputSchema: {
            type: 'object',
            required: %w[project_id title],
            properties: {
              project_id: { type: 'string', description: 'Project identifier (required)' },
              title:      { type: 'string', description: 'Wiki page title (required)' },
              version:    { type: 'integer', description: 'Specific version number (default: latest)' }
            }
          }
        },
        {
          name: 'create_update_wiki_page',
          description: 'Create or update a wiki page (upsert by title)',
          inputSchema: {
            type: 'object',
            required: %w[project_id title text],
            properties: {
              project_id: { type: 'string', description: 'Project identifier (required)' },
              title:      { type: 'string', description: 'Wiki page title (required)' },
              text:       { type: 'string', description: 'Wiki page content in Textile/Markdown (required)' },
              comments:   { type: 'string', description: 'Edit comment/summary' },
              parent_title:{ type: 'string', description: 'Parent page title' }
            }
          }
        },
        {
          name: 'delete_wiki_page',
          description: 'Delete a wiki page',
          inputSchema: {
            type: 'object',
            required: %w[project_id title],
            properties: {
              project_id: { type: 'string', description: 'Project identifier (required)' },
              title:      { type: 'string', description: 'Wiki page title (required)' }
            }
          }
        },

        # ── Memberships ───────────────────────────────────────────────────────
        {
          name: 'list_memberships',
          description: 'List project memberships',
          inputSchema: {
            type: 'object',
            required: ['project_id'],
            properties: {
              project_id: { type: 'string',  description: 'Project identifier (required)' },
              limit:      { type: 'integer', description: 'Max results' },
              offset:     { type: 'integer', description: 'Offset' }
            }
          }
        },
        {
          name: 'create_membership',
          description: 'Add a user or group to a project with roles',
          inputSchema: {
            type: 'object',
            required: %w[project_id role_ids],
            properties: {
              project_id: { type: 'string',  description: 'Project identifier (required)' },
              user_id:    { type: 'integer', description: 'User ID (user_id or group_id required)' },
              group_id:   { type: 'integer', description: 'Group ID (user_id or group_id required)' },
              role_ids:   { type: 'array', items: { type: 'integer' }, description: 'Role IDs to assign (required)' }
            }
          }
        },
        {
          name: 'update_membership',
          description: 'Update roles for a project membership',
          inputSchema: {
            type: 'object',
            required: %w[id role_ids],
            properties: {
              id:       { type: 'integer', description: 'Membership ID (required)' },
              role_ids: { type: 'array', items: { type: 'integer' }, description: 'New role IDs (required)' }
            }
          }
        },
        {
          name: 'delete_membership',
          description: 'Remove a user/group from a project',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Membership ID (required)' }
            }
          }
        },

        # ── Users ─────────────────────────────────────────────────────────────
        {
          name: 'get_current_user',
          description: 'Get the currently authenticated user',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'list_users',
          description: 'List Redmine users (requires admin privileges)',
          inputSchema: {
            type: 'object',
            properties: {
              status: { type: 'integer', description: '0=anonymous,1=active,2=registered,3=locked,4=all (default 1)' },
              name:   { type: 'string',  description: 'Filter by name/login' },
              limit:  { type: 'integer', description: 'Max results' },
              offset: { type: 'integer', description: 'Offset' }
            }
          }
        },
        {
          name: 'get_user',
          description: 'Get details of a user by ID',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'User ID (required)' }
            }
          }
        },
        {
          name: 'create_user',
          description: 'Create a new user (requires admin)',
          inputSchema: {
            type: 'object',
            required: %w[login firstname lastname mail],
            properties: {
              login:            { type: 'string',  description: 'Login name (required)' },
              firstname:        { type: 'string',  description: 'First name (required)' },
              lastname:         { type: 'string',  description: 'Last name (required)' },
              mail:             { type: 'string',  description: 'Email address (required)' },
              password:         { type: 'string',  description: 'Password' },
              admin:            { type: 'boolean', description: 'Grant admin privileges' },
              must_change_passwd:{ type: 'boolean', description: 'Force password change on login' }
            }
          }
        },
        {
          name: 'update_user',
          description: 'Update a user (requires admin)',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:        { type: 'integer', description: 'User ID (required)' },
              firstname: { type: 'string',  description: 'First name' },
              lastname:  { type: 'string',  description: 'Last name' },
              mail:      { type: 'string',  description: 'Email address' },
              password:  { type: 'string',  description: 'New password' },
              admin:     { type: 'boolean', description: 'Admin privileges' },
              status:    { type: 'integer', description: '1=active, 3=locked' }
            }
          }
        },
        {
          name: 'delete_user',
          description: 'Delete a user (requires admin)',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'User ID (required)' }
            }
          }
        },

        # ── Roles ─────────────────────────────────────────────────────────────
        {
          name: 'list_roles',
          description: 'List all roles',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'get_role',
          description: 'Get details of a role including permissions',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Role ID (required)' }
            }
          }
        },

        # ── Trackers / statuses / priorities ──────────────────────────────────
        {
          name: 'list_trackers',
          description: 'List all trackers (Bug, Feature, Support, etc.)',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'list_issue_statuses',
          description: 'List all issue statuses',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'list_issue_priorities',
          description: 'List issue priority enumerations',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'list_time_entry_activities',
          description: 'List time entry activity enumerations',
          inputSchema: { type: 'object', properties: {} }
        },
        {
          name: 'list_custom_fields',
          description: 'List all custom fields (requires admin)',
          inputSchema: { type: 'object', properties: {} }
        },

        # ── News ──────────────────────────────────────────────────────────────
        {
          name: 'list_news',
          description: 'List news items, optionally filtered by project',
          inputSchema: {
            type: 'object',
            properties: {
              project_id: { type: 'string',  description: 'Project identifier (omit for all projects)' },
              limit:      { type: 'integer', description: 'Max results (default 25)' },
              offset:     { type: 'integer', description: 'Offset' }
            }
          }
        },

        # ── Queries ───────────────────────────────────────────────────────────
        {
          name: 'list_queries',
          description: 'List saved issue queries',
          inputSchema: {
            type: 'object',
            properties: {
              project_id: { type: 'string',  description: 'Filter by project identifier' },
              limit:      { type: 'integer', description: 'Max results' },
              offset:     { type: 'integer', description: 'Offset' }
            }
          }
        },

        # ── Time entries ──────────────────────────────────────────────────────
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
          name: 'get_time_entry',
          description: 'Get details of a time entry',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Time entry ID (required)' }
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
              issue_id:    { type: 'integer', description: 'Issue ID (or project_id required)' },
              project_id:  { type: 'string',  description: 'Project identifier (or issue_id required)' },
              hours:       { type: 'number',  description: 'Hours spent (required)' },
              activity_id: { type: 'integer', description: 'Activity type ID (required)' },
              comments:    { type: 'string',  description: 'Comments' },
              spent_on:    { type: 'string',  description: 'Date (YYYY-MM-DD, default today)' }
            }
          }
        },
        {
          name: 'update_time_entry',
          description: 'Update an existing time entry',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id:          { type: 'integer', description: 'Time entry ID (required)' },
              hours:       { type: 'number',  description: 'New hours value' },
              activity_id: { type: 'integer', description: 'New activity ID' },
              comments:    { type: 'string',  description: 'New comments' },
              spent_on:    { type: 'string',  description: 'New date (YYYY-MM-DD)' }
            }
          }
        },
        {
          name: 'delete_time_entry',
          description: 'Delete a time entry',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Time entry ID (required)' }
            }
          }
        },

        # ── Attachments ───────────────────────────────────────────────────────
        {
          name: 'get_attachment',
          description: 'Get details of an attachment',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Attachment ID (required)' }
            }
          }
        },
        {
          name: 'delete_attachment',
          description: 'Delete an attachment',
          inputSchema: {
            type: 'object',
            required: ['id'],
            properties: {
              id: { type: 'integer', description: 'Attachment ID (required)' }
            }
          }
        },
        {
          name: 'upload_file',
          description: 'Upload a file to Redmine and get an upload token. Use the returned token in create_issue or update_issue uploads array.',
          inputSchema: {
            type: 'object',
            required: %w[filename data],
            properties: {
              filename:     { type: 'string', description: 'File name including extension (e.g. screenshot.png)' },
              data:         { type: 'string', description: 'Base64-encoded file content' },
              content_type: { type: 'string', description: 'MIME type (e.g. image/png). Auto-detected if omitted.' },
              description:  { type: 'string', description: 'Optional description for the attachment' }
            }
          }
        },

        # ── Search ────────────────────────────────────────────────────────────
        {
          name: 'search',
          description: 'Search issues and projects by keyword',
          inputSchema: {
            type: 'object',
            required: ['query'],
            properties: {
              query:      { type: 'string',  description: 'Search keyword (required)' },
              project_id: { type: 'string',  description: 'Scope to a project identifier' },
              limit:      { type: 'integer', description: 'Max results (default 25)' }
            }
          }
        }
      ]
    end

    # ── Tool dispatch ──────────────────────────────────────────────────────────

    def self.call(name, args, user)
      case name
      # Projects
      when 'list_projects'    then list_projects(args, user)
      when 'get_project'      then get_project(args, user)
      when 'create_project'   then create_project(args, user)
      when 'update_project'   then update_project(args, user)
      when 'delete_project'   then delete_project(args, user)
      # Issues
      when 'list_issues'      then list_issues(args, user)
      when 'get_issue'        then get_issue(args, user)
      when 'create_issue'     then create_issue(args, user)
      when 'update_issue'     then update_issue(args, user)
      when 'delete_issue'     then delete_issue(args, user)
      # Issue categories
      when 'list_issue_categories'  then list_issue_categories(args, user)
      when 'create_issue_category'  then create_issue_category(args, user)
      when 'update_issue_category'  then update_issue_category(args, user)
      when 'delete_issue_category'  then delete_issue_category(args, user)
      # Versions
      when 'list_versions'    then list_versions(args, user)
      when 'get_version'      then get_version(args, user)
      when 'create_version'   then create_version(args, user)
      when 'update_version'   then update_version(args, user)
      when 'delete_version'   then delete_version(args, user)
      # Wiki
      when 'list_wiki_pages'        then list_wiki_pages(args, user)
      when 'get_wiki_page'          then get_wiki_page(args, user)
      when 'create_update_wiki_page' then create_update_wiki_page(args, user)
      when 'delete_wiki_page'       then delete_wiki_page(args, user)
      # Memberships
      when 'list_memberships'   then list_memberships(args, user)
      when 'create_membership'  then create_membership(args, user)
      when 'update_membership'  then update_membership(args, user)
      when 'delete_membership'  then delete_membership(args, user)
      # Users
      when 'get_current_user'   then get_current_user(args, user)
      when 'list_users'         then list_users(args, user)
      when 'get_user'           then get_user(args, user)
      when 'create_user'        then create_user(args, user)
      when 'update_user'        then update_user(args, user)
      when 'delete_user'        then delete_user(args, user)
      # Roles
      when 'list_roles'   then list_roles(args, user)
      when 'get_role'     then get_role(args, user)
      # Enumerations / reference data
      when 'list_trackers'              then list_trackers(args, user)
      when 'list_issue_statuses'        then list_issue_statuses(args, user)
      when 'list_issue_priorities'      then list_issue_priorities(args, user)
      when 'list_time_entry_activities' then list_time_entry_activities(args, user)
      when 'list_custom_fields'         then list_custom_fields(args, user)
      # News
      when 'list_news'    then list_news(args, user)
      # Queries
      when 'list_queries' then list_queries(args, user)
      # Time entries
      when 'list_time_entries'  then list_time_entries(args, user)
      when 'get_time_entry'     then get_time_entry(args, user)
      when 'create_time_entry'  then create_time_entry(args, user)
      when 'update_time_entry'  then update_time_entry(args, user)
      when 'delete_time_entry'  then delete_time_entry(args, user)
      # Attachments
      when 'get_attachment'     then get_attachment(args, user)
      when 'delete_attachment'  then delete_attachment(args, user)
      when 'upload_file'        then upload_file(args, user)
      # Search
      when 'search'       then search(args, user)
      else raise "Unknown tool: #{name}"
      end
    end

    # ── Implementations ────────────────────────────────────────────────────────

    # ── Projects ──────────────────────────────────────────────────────────────

    def self.list_projects(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = Project.visible(user)
      total  = scope.count
      items  = scope.order(:name).offset(offset).limit(limit)
      { projects: items.map { |p| serialize_project(p) }, total_count: total, offset: offset, limit: limit }
    end

    def self.get_project(args, user)
      project = find_project(args['id'], user)
      raise "Project not found: #{args['id']}" unless project
      serialize_project(project, detailed: true)
    end

    def self.create_project(args, user)
      project = Project.new(
        name:        args['name'],
        identifier:  args['identifier'],
        description: args['description'],
        is_public:   args.key?('is_public') ? args['is_public'] : true
      )
      project.parent_id = args['parent_id'] if args['parent_id']
      if args['tracker_ids']
        project.tracker_ids = args['tracker_ids']
      else
        project.trackers = Tracker.all
      end
      raise "Failed to create project: #{project.errors.full_messages.join(', ')}" unless project.save
      serialize_project(project, detailed: true)
    end

    def self.update_project(args, user)
      project = find_project(args['id'], user)
      raise "Project not found: #{args['id']}" unless project

      project.name        = args['name']        if args['name']
      project.description = args['description'] if args.key?('description')
      project.is_public   = args['is_public']   if args.key?('is_public')
      project.parent_id   = args['parent_id']   if args['parent_id']
      project.tracker_ids = args['tracker_ids'] if args['tracker_ids']

      raise "Failed to update project: #{project.errors.full_messages.join(', ')}" unless project.save
      serialize_project(project, detailed: true)
    end

    def self.delete_project(args, user)
      raise 'Admin privileges required to delete projects' unless user.admin?
      project = find_project(args['id'], user)
      raise "Project not found: #{args['id']}" unless project
      raise "Failed to delete project" unless project.destroy
      { deleted: true, id: project.id, name: project.name }
    end

    # ── Issues ────────────────────────────────────────────────────────────────

    def self.list_issues(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = Issue.visible(user).includes(:status, :tracker, :priority, :assigned_to)

      if args['project_id']
        project = find_project(args['project_id'], user)
        scope = scope.where(project_id: project.id) if project
      end

      scope = scope.where(tracker_id:  args['tracker_id'].to_i)  if args['tracker_id']
      scope = scope.where(category_id: args['category_id'].to_i) if args['category_id']
      scope = scope.where(fixed_version_id: args['version_id'].to_i) if args['version_id']
      scope = scope.where(priority_id: args['priority_id'].to_i) if args['priority_id']
      scope = scope.where(author_id:   args['author_id'].to_i)   if args['author_id']

      case args['status_id'].to_s
      when 'open', '' then scope = scope.open
      when 'closed'   then scope = scope.where(status: IssueStatus.where(is_closed: true))
      when '*'        then nil # no filter
      else                 scope = scope.where(status_id: args['status_id'].to_i)
      end

      if args['assigned_to_id'].to_s == 'me'
        scope = scope.where(assigned_to_id: user.id)
      elsif args['assigned_to_id']
        scope = scope.where(assigned_to_id: args['assigned_to_id'].to_i)
      end

      if args['created_on']
        scope = apply_date_filter(scope, 'issues.created_on', args['created_on'])
      end
      if args['updated_on']
        scope = apply_date_filter(scope, 'issues.updated_on', args['updated_on'])
      end

      sort_field, sort_dir = (args['sort'] || 'id:desc').split(':')
      sort_dir = %w[asc desc].include?(sort_dir) ? sort_dir : 'asc'
      begin
        scope = scope.order(Arel.sql("issues.#{ActiveRecord::Base.connection.quote_column_name(sort_field)} #{sort_dir}"))
      rescue
        scope = scope.order('issues.id desc')
      end

      total = scope.count
      items = scope.offset(offset).limit(limit)
      { issues: items.map { |i| serialize_issue_brief(i) }, total_count: total, offset: offset, limit: limit }
    end

    def self.get_issue(args, user)
      issue = Issue.visible(user)
                   .includes(:status, :tracker, :priority, :assigned_to,
                             :author, :attachments, journals: :user)
                   .find_by(id: args['id'].to_i)
      raise "Issue ##{args['id']} not found" unless issue
      serialize_issue(issue)
    end

    def self.create_issue(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project

      issue = Issue.new(
        project:          project,
        author:           user,
        subject:          args['subject'],
        description:      args['description'],
        tracker_id:       args['tracker_id']       || project.trackers.first&.id,
        status_id:        args['status_id']        || IssueStatus.where(is_closed: false).order(:position).first&.id,
        priority_id:      args['priority_id']      || IssuePriority.default&.id,
        assigned_to_id:   args['assigned_to_id'],
        category_id:      args['category_id'],
        fixed_version_id: args['fixed_version_id'],
        parent_issue_id:  args['parent_issue_id'],
        start_date:       args['start_date'],
        due_date:         args['due_date'],
        estimated_hours:  args['estimated_hours'],
        done_ratio:       args['done_ratio']
      )
      raise "Failed to create issue: #{issue.errors.full_messages.join(', ')}" unless issue.save
      attach_uploads(issue, args['uploads'], user) if args['uploads'].present?
      serialize_issue(issue.reload)
    end

    def self.update_issue(args, user)
      issue = Issue.visible(user).find_by(id: args['id'].to_i)
      raise "Issue ##{args['id']} not found" unless issue

      issue.init_journal(user, args['notes']) if args['notes'].present?

      updatable = %w[subject description status_id priority_id assigned_to_id
                     category_id fixed_version_id parent_issue_id
                     done_ratio due_date start_date estimated_hours]
      attrs = args.slice(*updatable).reject { |_, v| v.nil? }
      issue.assign_attributes(attrs) unless attrs.empty?

      raise "Failed to update issue: #{issue.errors.full_messages.join(', ')}" unless issue.save
      attach_uploads(issue, args['uploads'], user) if args['uploads'].present?
      serialize_issue(issue.reload)
    end

    def self.delete_issue(args, user)
      issue = Issue.visible(user).find_by(id: args['id'].to_i)
      raise "Issue ##{args['id']} not found" unless issue
      raise "Not authorized to delete issue ##{args['id']}" unless user.allowed_to?(:delete_issues, issue.project)
      raise "Failed to delete issue" unless issue.destroy
      { deleted: true, id: issue.id }
    end

    # ── Issue categories ──────────────────────────────────────────────────────

    def self.list_issue_categories(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      categories = project.issue_categories.includes(:assigned_to)
      { issue_categories: categories.map { |c| serialize_issue_category(c) } }
    end

    def self.create_issue_category(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      cat = IssueCategory.new(project: project, name: args['name'], assigned_to_id: args['assigned_to_id'])
      raise "Failed to create category: #{cat.errors.full_messages.join(', ')}" unless cat.save
      serialize_issue_category(cat)
    end

    def self.update_issue_category(args, user)
      cat = IssueCategory.find_by(id: args['id'].to_i)
      raise "Category not found: #{args['id']}" unless cat
      cat.name           = args['name']           if args['name']
      cat.assigned_to_id = args['assigned_to_id'] if args.key?('assigned_to_id')
      raise "Failed to update category: #{cat.errors.full_messages.join(', ')}" unless cat.save
      serialize_issue_category(cat)
    end

    def self.delete_issue_category(args, user)
      cat = IssueCategory.find_by(id: args['id'].to_i)
      raise "Category not found: #{args['id']}" unless cat
      cat.destroy
      { deleted: true, id: cat.id }
    end

    # ── Versions ──────────────────────────────────────────────────────────────

    def self.list_versions(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      { versions: project.versions.map { |v| serialize_version(v) } }
    end

    def self.get_version(args, user)
      v = Version.find_by(id: args['id'].to_i)
      raise "Version not found: #{args['id']}" unless v
      serialize_version(v)
    end

    def self.create_version(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      v = Version.new(
        project:     project,
        name:        args['name'],
        description: args['description'],
        status:      args['status'] || 'open',
        due_date:    args['due_date'],
        sharing:     args['sharing'] || 'none'
      )
      raise "Failed to create version: #{v.errors.full_messages.join(', ')}" unless v.save
      serialize_version(v)
    end

    def self.update_version(args, user)
      v = Version.find_by(id: args['id'].to_i)
      raise "Version not found: #{args['id']}" unless v
      %w[name description status due_date sharing].each do |f|
        v.send(:"#{f}=", args[f]) if args.key?(f)
      end
      raise "Failed to update version: #{v.errors.full_messages.join(', ')}" unless v.save
      serialize_version(v)
    end

    def self.delete_version(args, user)
      v = Version.find_by(id: args['id'].to_i)
      raise "Version not found: #{args['id']}" unless v
      v.destroy
      { deleted: true, id: v.id }
    end

    # ── Wiki ──────────────────────────────────────────────────────────────────

    def self.list_wiki_pages(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      wiki = project.wiki
      raise "Wiki not enabled for this project" unless wiki
      pages = wiki.pages.includes(:parent)
      { wiki_pages: pages.map { |p| { id: p.id, title: p.title, parent_title: p.parent&.title, updated_on: p.updated_on&.iso8601 } } }
    end

    def self.get_wiki_page(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      wiki = project.wiki
      raise "Wiki not enabled for this project" unless wiki

      title = Wiki.titleize(args['title'])
      page  = wiki.find_page(title)
      raise "Wiki page '#{args['title']}' not found" unless page

      content = args['version'] ? page.content_for_version(args['version'].to_i) : page.content
      {
        id:           page.id,
        title:        page.title,
        text:         content&.text.to_s,
        version:      content&.version,
        author:       content&.author ? { id: content.author.id, name: content.author.name } : nil,
        parent_title: page.parent&.title,
        created_on:   page.created_on&.iso8601,
        updated_on:   page.updated_on&.iso8601
      }
    end

    def self.create_update_wiki_page(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project

      wiki = project.wiki
      unless wiki
        project.enable_module!(:wiki)
        wiki = Wiki.create!(project: project, start_page: 'WikiStart')
      end

      title = Wiki.titleize(args['title'])
      page  = wiki.find_or_new_page(title)

      page.content ||= WikiContent.new(page: page)
      page.content.text     = args['text']
      page.content.comments = args['comments'].to_s
      page.content.author   = user

      if args['parent_title']
        parent = wiki.find_page(Wiki.titleize(args['parent_title']))
        page.parent = parent
      end

      raise "Failed to save wiki page: #{page.content.errors.full_messages.join(', ')}" unless page.content.save
      page.save if page.new_record? || page.changed?

      get_wiki_page({ 'project_id' => args['project_id'], 'title' => args['title'] }, user)
    end

    def self.delete_wiki_page(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      wiki = project.wiki
      raise "Wiki not enabled for this project" unless wiki
      title = Wiki.titleize(args['title'])
      page  = wiki.find_page(title)
      raise "Wiki page '#{args['title']}' not found" unless page
      page.destroy
      { deleted: true, title: page.title }
    end

    # ── Memberships ───────────────────────────────────────────────────────────

    def self.list_memberships(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = project.memberships.includes(:principal, :roles)
      total  = scope.count
      items  = scope.offset(offset).limit(limit)
      { memberships: items.map { |m| serialize_membership(m) }, total_count: total }
    end

    def self.create_membership(args, user)
      project = find_project(args['project_id'], user)
      raise "Project not found: #{args['project_id']}" unless project
      raise "user_id or group_id is required" unless args['user_id'] || args['group_id']

      principal_id = args['user_id'] || args['group_id']
      membership = project.memberships.build
      membership.principal = Principal.find(principal_id)
      membership.role_ids = args['role_ids']
      raise "Failed to create membership: #{membership.errors.full_messages.join(', ')}" unless membership.save
      serialize_membership(membership)
    end

    def self.update_membership(args, user)
      membership = Member.find_by(id: args['id'].to_i)
      raise "Membership not found: #{args['id']}" unless membership
      membership.role_ids = args['role_ids']
      raise "Failed to update membership: #{membership.errors.full_messages.join(', ')}" unless membership.save
      serialize_membership(membership)
    end

    def self.delete_membership(args, user)
      membership = Member.find_by(id: args['id'].to_i)
      raise "Membership not found: #{args['id']}" unless membership
      membership.destroy
      { deleted: true, id: membership.id }
    end

    # ── Users ─────────────────────────────────────────────────────────────────

    def self.get_current_user(_args, user)
      serialize_user(user, detailed: true)
    end

    def self.list_users(args, user)
      raise 'Admin privileges required to list users' unless user.admin?
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = User.where.not(type: 'AnonymousUser')
      scope  = scope.status(args['status'].to_i) if args['status']
      scope  = scope.where("login LIKE ? OR firstname LIKE ? OR lastname LIKE ?",
                           "%#{args['name']}%", "%#{args['name']}%", "%#{args['name']}%") if args['name']
      total = scope.count
      items = scope.order(:login).offset(offset).limit(limit)
      { users: items.map { |u| serialize_user(u) }, total_count: total, offset: offset, limit: limit }
    end

    def self.get_user(args, user)
      raise 'Admin privileges required to view users' unless user.admin? || user.id == args['id'].to_i
      u = User.find_by(id: args['id'].to_i)
      raise "User not found: #{args['id']}" unless u
      serialize_user(u, detailed: true)
    end

    def self.create_user(args, user)
      raise 'Admin privileges required to create users' unless user.admin?
      u = User.new(
        login:             args['login'],
        firstname:         args['firstname'],
        lastname:          args['lastname'],
        mail:              args['mail'],
        admin:             args['admin'] || false,
        must_change_passwd: args['must_change_passwd'] || false
      )
      u.password              = args['password'] if args['password']
      u.password_confirmation = args['password'] if args['password']
      raise "Failed to create user: #{u.errors.full_messages.join(', ')}" unless u.save
      serialize_user(u, detailed: true)
    end

    def self.update_user(args, user)
      raise 'Admin privileges required to update users' unless user.admin?
      u = User.find_by(id: args['id'].to_i)
      raise "User not found: #{args['id']}" unless u
      %w[firstname lastname mail admin status].each { |f| u.send(:"#{f}=", args[f]) if args.key?(f) }
      if args['password']
        u.password = u.password_confirmation = args['password']
      end
      raise "Failed to update user: #{u.errors.full_messages.join(', ')}" unless u.save
      serialize_user(u, detailed: true)
    end

    def self.delete_user(args, user)
      raise 'Admin privileges required to delete users' unless user.admin?
      u = User.find_by(id: args['id'].to_i)
      raise "User not found: #{args['id']}" unless u
      raise "Cannot delete yourself" if u.id == user.id
      u.destroy
      { deleted: true, id: u.id, login: u.login }
    end

    # ── Roles ─────────────────────────────────────────────────────────────────

    def self.list_roles(_args, _user)
      { roles: Role.givable.map { |r| { id: r.id, name: r.name } } }
    end

    def self.get_role(args, _user)
      r = Role.find_by(id: args['id'].to_i)
      raise "Role not found: #{args['id']}" unless r
      { id: r.id, name: r.name, permissions: r.permissions.map(&:to_s) }
    end

    # ── Enumerations / reference data ─────────────────────────────────────────

    def self.list_trackers(_args, _user)
      { trackers: Tracker.all.order(:position).map { |t| { id: t.id, name: t.name } } }
    end

    def self.list_issue_statuses(_args, _user)
      { issue_statuses: IssueStatus.all.order(:position).map { |s| { id: s.id, name: s.name, is_closed: s.is_closed } } }
    end

    def self.list_issue_priorities(_args, _user)
      { issue_priorities: IssuePriority.all.order(:position).map { |p| { id: p.id, name: p.name, is_default: p.is_default } } }
    end

    def self.list_time_entry_activities(_args, _user)
      { time_entry_activities: TimeEntryActivity.all.order(:position).map { |a| { id: a.id, name: a.name, is_default: a.is_default } } }
    end

    def self.list_custom_fields(_args, user)
      raise 'Admin privileges required to list custom fields' unless user.admin?
      { custom_fields: CustomField.all.map { |f| { id: f.id, name: f.name, type: f.type, field_format: f.field_format } } }
    end

    # ── News ──────────────────────────────────────────────────────────────────

    def self.list_news(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = News.visible(user).includes(:project, :author)
      if args['project_id']
        project = find_project(args['project_id'], user)
        scope = scope.where(project_id: project.id) if project
      end
      total = scope.count
      items = scope.order(created_on: :desc).offset(offset).limit(limit)
      {
        news: items.map { |n|
          { id: n.id, project: { id: n.project_id, name: n.project&.name },
            title: n.title, summary: n.summary, description: n.description.to_s.truncate(500),
            author: { id: n.author_id, name: n.author&.name }, created_on: n.created_on&.iso8601 }
        },
        total_count: total, offset: offset, limit: limit
      }
    end

    # ── Queries ───────────────────────────────────────────────────────────────

    def self.list_queries(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = IssueQuery.visible(user)
      if args['project_id']
        project = find_project(args['project_id'], user)
        scope = scope.where(project_id: [nil, project&.id])
      end
      total = scope.count
      items = scope.order(:name).offset(offset).limit(limit)
      { queries: items.map { |q| { id: q.id, name: q.name, is_public: q.is_public, project_id: q.project_id } },
        total_count: total, offset: offset, limit: limit }
    end

    # ── Time entries ──────────────────────────────────────────────────────────

    def self.list_time_entries(args, user)
      limit  = (args['limit']  || 25).to_i.clamp(1, 100)
      offset = (args['offset'] || 0).to_i
      scope  = TimeEntry.visible(user).includes(:project, :issue, :activity)
      if args['project_id']
        project = find_project(args['project_id'], user)
        scope = scope.where(project_id: project.id) if project
      end
      scope = scope.where(issue_id:  args['issue_id'].to_i) if args['issue_id']
      scope = scope.where(user_id:   args['user_id'].to_i)  if args['user_id']
      scope = scope.where('spent_on >= ?', args['from'])     if args['from']
      scope = scope.where('spent_on <= ?', args['to'])       if args['to']
      total = scope.count
      items = scope.order(spent_on: :desc).offset(offset).limit(limit)
      { time_entries: items.map { |t| serialize_time_entry(t) }, total_count: total, offset: offset, limit: limit }
    end

    def self.get_time_entry(args, user)
      entry = TimeEntry.visible(user).find_by(id: args['id'].to_i)
      raise "Time entry not found: #{args['id']}" unless entry
      serialize_time_entry(entry)
    end

    def self.create_time_entry(args, user)
      project_id = nil
      if args['project_id']
        project    = find_project(args['project_id'], user)
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
      entry.project_id ||= Issue.find_by(id: entry.issue_id)&.project_id
      raise "Failed to log time: #{entry.errors.full_messages.join(', ')}" unless entry.save
      serialize_time_entry(entry)
    end

    def self.update_time_entry(args, user)
      entry = TimeEntry.visible(user).find_by(id: args['id'].to_i)
      raise "Time entry not found: #{args['id']}" unless entry
      %w[hours activity_id comments spent_on].each { |f| entry.send(:"#{f}=", args[f]) if args.key?(f) }
      raise "Failed to update time entry: #{entry.errors.full_messages.join(', ')}" unless entry.save
      serialize_time_entry(entry)
    end

    def self.delete_time_entry(args, user)
      entry = TimeEntry.visible(user).find_by(id: args['id'].to_i)
      raise "Time entry not found: #{args['id']}" unless entry
      entry.destroy
      { deleted: true, id: entry.id }
    end

    # ── Attachments ───────────────────────────────────────────────────────────

    def self.get_attachment(args, user)
      a = Attachment.find_by(id: args['id'].to_i)
      raise "Attachment not found: #{args['id']}" unless a
      raise "Not authorized" unless a.visible?(user)
      serialize_attachment(a)
    end

    def self.delete_attachment(args, user)
      a = Attachment.find_by(id: args['id'].to_i)
      raise "Attachment not found: #{args['id']}" unless a
      raise "Not authorized to delete this attachment" unless a.deletable?(user)
      a.destroy
      { deleted: true, id: a.id, filename: a.filename }
    end

    def self.upload_file(args, user)
      filename     = args['filename'].to_s.presence || 'upload'
      content_type = args['content_type'].to_s.presence || 'application/octet-stream'
      data         = args['data'].to_s
      description  = args['description'].to_s
      raise 'data (base64) is required' if data.blank?

      binary = Base64.decode64(data)
      tmp = Tempfile.new(['mcp_upload', File.extname(filename)])
      tmp.binmode
      tmp.write(binary)
      tmp.rewind

      uploaded = ActionDispatch::Http::UploadedFile.new(
        filename: filename, type: content_type, tempfile: tmp
      )
      attachment = Attachment.new(
        file: uploaded, filename: filename,
        content_type: content_type, description: description, author: user
      )
      raise "Upload failed: #{attachment.errors.full_messages.join(', ')}" unless attachment.save
      { token: attachment.token, id: attachment.id, filename: filename, filesize: attachment.filesize }
    ensure
      tmp&.close
      tmp&.unlink
    end

    def self.attach_uploads(container, uploads, user)
      return if uploads.blank?
      uploads_hash = uploads.each_with_index.each_with_object({}) do |(upload, i), h|
        h[i.to_s] = {
          'token'       => upload['token'].to_s,
          'filename'    => upload['filename'].to_s,
          'description' => upload['description'].to_s
        }
      end
      saved, _failed = Attachment.attach_files(container, uploads_hash)
      container.save if saved.any?
    end

    # ── Search ────────────────────────────────────────────────────────────────

    def self.search(args, user)
      q     = args['query'].to_s.strip
      limit = (args['limit'] || 25).to_i.clamp(1, 100)
      raise 'Search query required' if q.blank?

      pattern  = "%#{q}%"
      results  = []

      issue_scope = Issue.visible(user)
                         .where('issues.subject LIKE ? OR issues.description LIKE ?', pattern, pattern)
                         .includes(:project, :status)
      if args['project_id']
        project = find_project(args['project_id'], user)
        issue_scope = issue_scope.where(project_id: project.id) if project
      end
      results += issue_scope.limit(limit).map do |i|
        { type: 'issue', id: i.id, title: i.subject,
          project: i.project.name, status: i.status.name, url: "/issues/#{i.id}" }
      end

      unless args['project_id']
        results += Project.visible(user)
                          .where('projects.name LIKE ? OR projects.description LIKE ?', pattern, pattern)
                          .limit(10)
                          .map { |p| { type: 'project', id: p.id, title: p.name, url: "/projects/#{p.identifier}" } }
      end

      { results: results, total_count: results.size }
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    def self.find_project(id, user)
      id = id.to_s
      if id.match?(/\A\d+\z/)
        Project.visible(user).find_by(id: id.to_i)
      else
        Project.visible(user).find_by(identifier: id)
      end
    end

    def self.apply_date_filter(scope, column, value)
      case value.to_s
      when /\A>=(.+)\z/ then scope.where("#{column} >= ?", $1.strip)
      when /\A<=(.+)\z/ then scope.where("#{column} <= ?", $1.strip)
      when /\A>(.+)\z/  then scope.where("#{column} > ?",  $1.strip)
      when /\A<(.+)\z/  then scope.where("#{column} < ?",  $1.strip)
      when /\A(.+)\|(.+)\z/ then scope.where("#{column} BETWEEN ? AND ?", $1.strip, $2.strip)
      else scope.where("#{column} = ?", value.strip)
      end
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
        h[:versions]         = p.versions.map { |v| { id: v.id, name: v.name, status: v.status } }
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
        description:      i.description.to_s,
        author:           { id: i.author_id, name: i.author&.name },
        category:         i.category ? { id: i.category.id, name: i.category.name } : nil,
        fixed_version:    i.fixed_version ? { id: i.fixed_version.id, name: i.fixed_version.name } : nil,
        parent:           i.parent_id ? { id: i.parent_id } : nil,
        start_date:       i.start_date&.iso8601,
        due_date:         i.due_date&.iso8601,
        estimated_hours:  i.estimated_hours,
        spent_hours:      i.spent_hours,
        closed_on:        i.closed_on&.iso8601
      )
      if i.association(:attachments).loaded?
        h[:attachments] = i.attachments.map { |a| serialize_attachment(a) }
      end
      if i.association(:journals).loaded?
        h[:journals] = i.journals.map do |j|
          { id: j.id, user: { id: j.user_id, name: j.user&.name },
            notes: j.notes, created_on: j.created_on&.iso8601,
            details: j.details.map { |d| { property: d.property, name: d.prop_key, old_value: d.old_value, new_value: d.value } } }
        end
      end
      h
    end

    def self.serialize_issue_category(c)
      { id: c.id, name: c.name,
        assigned_to: c.assigned_to ? { id: c.assigned_to.id, name: c.assigned_to.name } : nil }
    end

    def self.serialize_version(v)
      { id: v.id, name: v.name, description: v.description,
        status: v.status, due_date: v.due_date&.iso8601, sharing: v.sharing,
        project: { id: v.project_id, name: v.project&.name },
        created_on: v.created_on&.iso8601, updated_on: v.updated_on&.iso8601 }
    end

    def self.serialize_membership(m)
      { id: m.id,
        principal: { id: m.principal_id, name: m.principal&.name, type: m.principal&.class&.name },
        roles: m.roles.map { |r| { id: r.id, name: r.name } },
        project: { id: m.project_id } }
    end

    def self.serialize_user(u, detailed: false)
      h = {
        id:         u.id,
        login:      u.login,
        firstname:  u.firstname,
        lastname:   u.lastname,
        name:       u.name,
        mail:       u.mail,
        admin:      u.admin?,
        status:     u.status,
        created_on: u.created_on&.iso8601
      }
      h[:last_login_on] = u.last_login_on&.iso8601 if detailed
      h
    end

    def self.serialize_time_entry(t)
      { id: t.id,
        project:  { id: t.project_id, name: t.project&.name },
        issue:    t.issue_id ? { id: t.issue_id } : nil,
        user:     { id: t.user_id, name: t.user&.name },
        activity: { id: t.activity_id, name: t.activity&.name },
        hours:    t.hours,
        comments: t.comments,
        spent_on: t.spent_on&.iso8601,
        created_on: t.created_on&.iso8601 }
    end

    def self.serialize_attachment(a)
      { id: a.id, filename: a.filename, filesize: a.filesize,
        content_type: a.content_type, description: a.description,
        author: { id: a.author_id, name: a.author&.name },
        created_on: a.created_on&.iso8601 }
    end
  end
end
