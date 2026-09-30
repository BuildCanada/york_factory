module Mcp
  # What a tool, resource or prompt knows about the MCP request it serves:
  # the authenticated caller (Keys::Caller, from an API key or an OAuth
  # token), the in-process /v1 client and the meter that counts its units.
  # Passed to the gem as the server context; tools read it as
  # `server_context[:mcp]`.
  Context = Data.define(:caller, :api, :meter, :locale, :request_id) do
    def scope?(scope) = caller.scope?(scope)
  end
end
