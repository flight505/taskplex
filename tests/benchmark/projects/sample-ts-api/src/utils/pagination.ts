// BUG: S002 — off-by-one in slice. limit=10 returns 9 items.

export interface PaginationOptions {
  offset: number;
  limit: number;
}

export interface PaginatedResult<T> {
  items: T[];
  total: number;
  offset: number;
  limit: number;
  hasMore: boolean;
}

export function paginate<T>(
  items: T[],
  options: PaginationOptions
): PaginatedResult<T> {
  const { offset, limit } = options;
  const total = items.length;
  // BUG: should be offset + limit, not offset + limit - 1
  const sliced = items.slice(offset, offset + limit - 1);

  return {
    items: sliced,
    total,
    offset,
    limit,
    hasMore: offset + limit < total,
  };
}
