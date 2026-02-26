import { describe, it, expect } from "vitest";
import { paginate } from "../../src/utils/pagination.js";

describe("paginate", () => {
  const items = Array.from({ length: 25 }, (_, i) => i + 1);

  it("returns the correct number of items", () => {
    const result = paginate(items, { offset: 0, limit: 10 });
    // This test currently FAILS due to the off-by-one bug (S002)
    expect(result.items).toHaveLength(10);
  });

  it("respects offset", () => {
    const result = paginate(items, { offset: 5, limit: 5 });
    expect(result.items[0]).toBe(6);
  });

  it("returns empty for offset beyond array", () => {
    const result = paginate(items, { offset: 100, limit: 10 });
    expect(result.items).toHaveLength(0);
  });

  it("reports hasMore correctly", () => {
    const result = paginate(items, { offset: 0, limit: 10 });
    expect(result.hasMore).toBe(true);

    const last = paginate(items, { offset: 20, limit: 10 });
    expect(last.hasMore).toBe(false);
  });

  it("includes total count", () => {
    const result = paginate(items, { offset: 0, limit: 10 });
    expect(result.total).toBe(25);
  });
});
