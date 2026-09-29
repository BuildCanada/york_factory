// Shared e2e checks for both SDK generations. `client` is connected.
export async function exercise(client, label) {
  const out = [];
  const check = (ok, what) => { out.push(`${ok ? "PASS" : "FAIL"} ${label}: ${what}`); if (!ok) process.exitCode = 1; };
  const tools = (await client.listTools()).tools;
  check(tools.map(t => t.name).join(",") === "search_entities,get_entity,entity_spending,search_spending,describe_data", "tools/list has the 5 tools");
  check(tools.every(t => t.outputSchema && t.annotations?.readOnlyHint === true), "every tool has outputSchema and readOnlyHint");
  const search = await client.callTool({ name: "search_entities", arguments: { query: "Diamond Valley", jurisdiction: "ca-ab" } });
  const id = search.structuredContent?.data?.[0]?.entity?.id;
  check(!search.isError && id === "gid://buildcanada/Entity/01J9ZK4T6M8Q2R5V7X3B1N0C4D", "search_entities finds Diamond Valley (structuredContent validated by the SDK)");
  const release = String(search.structuredContent.meta.release);
  const entity = await client.callTool({ name: "get_entity", arguments: { id, include: ["identifiers", "lineage"], as_of: release } });
  check(entity.structuredContent?.lineage?.predecessors?.length === 2, "get_entity returns two predecessors");
  const spending = await client.callTool({ name: "entity_spending", arguments: { id, fiscal_year: "2024-25", as_of: release } });
  const codes = spending.structuredContent?.summary?.meta?.caveats?.map(c => c.code) || [];
  check(codes.includes("not_cross_source_total") && spending.content[0].text.includes("Cite:"), "entity_spending has caveats and citations");
  const rows = await client.callTool({ name: "search_spending", arguments: { recipient: id, sort: "-amount", limit: 3, as_of: release } });
  check(rows.structuredContent?.data?.length === 3 && rows.structuredContent.citations.length === 3, "search_spending returns cited rows");
  const semantics = await client.callTool({ name: "describe_data", arguments: { topic: "spending semantics" } });
  check(semantics.structuredContent?.kind === "spending_semantics", "describe_data spending semantics");
  const person = await client.callTool({ name: "get_entity", arguments: { id: "01JD0000000000000000000PRS" } });
  check(!person.isError && person.structuredContent?.entity?.data?.entity_class === "person", "get_entity returns a person under read:public");
  const missing = await client.callTool({ name: "get_entity", arguments: { id: "01JD0000000000000000000ZZZ" } });
  check(missing.isError === true && missing.structuredContent?.error?.code === "not_found", "an unknown entity is a structured not_found (and passes SDK schema validation)");
  const bad = await client.callTool({ name: "search_spending", arguments: { fiscal_year: "2024-26" } });
  check(bad.isError === true && bad.structuredContent?.error?.code === "invalid_parameter", "a contract-refused argument is a structured invalid_parameter");
  const resources = (await client.listResources()).resources.map(r => r.uri);
  check(resources.includes("buildcanada://releases/latest"), "resources/list");
  const latest = await client.readResource({ uri: "buildcanada://releases/latest" });
  check(JSON.parse(latest.contents[0].text).data.number === 11, "resources/read releases/latest");
  const templates = (await client.listResourceTemplates()).resourceTemplates.map(t => t.uriTemplate);
  check(templates.includes("buildcanada://entities/{id}"), "resources/templates/list");
  const prompt = await client.getPrompt({ name: "investigate_recipient", arguments: { name: "Town of Diamond Valley" } });
  check(prompt.messages[0].content.text.includes("search_entities"), "prompts/get investigate_recipient");
  let unknown;
  try { await client.callTool({ name: "no_such_tool", arguments: {} }); } catch (e) { unknown = e; }
  check(unknown && /-32602|not found/i.test(String(unknown.code ?? "") + unknown.message), "an unknown tool is a protocol error");
  console.log(out.join("\n"));
}
