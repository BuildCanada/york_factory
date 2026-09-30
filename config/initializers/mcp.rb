# The MCP server lives in app/mcp as the Mcp namespace (app/mcp/server.rb is
# Mcp::Server, app/mcp/tools/get_entity.rb Mcp::Tools::GetEntity). The gem's
# own namespace is MCP.
module Mcp; end

Rails.autoloaders.main.push_dir(Rails.root.join("app/mcp"), namespace: Mcp)
