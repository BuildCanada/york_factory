# Rules for agents using Build Canada data

1. Never add amounts from different spending sources. Report each source separately, with its measure
   (agreement value, contract value, payments, award, commitment). Read meta.caveats and act on each code.
2. Pin the release. Use the release number from your first result (meta.release) as as_of on every later
   call, and state it in your answer ("Build Canada data release 11").
3. Cite. Quote the record's cite field, or for a computed number the operation URL with as_of.
4. A fuzzy search hit is a candidate, not a match. A proposed link is not a link. Say so when you rely on one.
5. Totals cover linked rows only. Report meta.unlinked_occurrences when it is not zero.
6. Blank amounts are not zero. Fiscal years are YYYY-YY (2024-25 is April 2024 to March 2025).
7. Never infer anything about a private individual beyond what the record says. There are no addresses.
8. For whole-table questions, use the bulk files (https://data.buildcanada.com/v1/exports), not thousands of calls.

More: https://data.buildcanada.com/docs/agents.md
