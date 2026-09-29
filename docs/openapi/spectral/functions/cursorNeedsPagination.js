// Spectral function: an operation with a `cursor` parameter must declare x-fern-pagination.
export default function cursorNeedsPagination(operation) {
  const params = operation?.parameters ?? [];
  const hasCursor = params.some((p) => p && p.name === "cursor");
  if (hasCursor && !operation["x-fern-pagination"]) {
    return [{ message: "An operation with a cursor parameter must declare x-fern-pagination." }];
  }
  if (!hasCursor && operation["x-fern-pagination"]) {
    return [{ message: "x-fern-pagination is declared but the operation has no cursor parameter." }];
  }
  return [];
}
