module McpAdminHelper
  def mcp_col_link(caption, col, cur_col, cur_dir, q)
    if cur_col == col
      new_dir = cur_dir == 'asc' ? 'desc' : 'asc'
      arrow   = cur_dir == 'asc' ? ' ↑' : ' ↓'
    else
      new_dir = 'asc'
      arrow   = ''
    end
    href  = mcp_admin_tokens_path(q.merge('sort' => "#{col}:#{new_dir}", 'page' => 1))
    klass = cur_col == col ? ' class="sorted"' : ''
    "<th#{klass}>#{link_to(caption + arrow, href)}</th>".html_safe
  end
end
