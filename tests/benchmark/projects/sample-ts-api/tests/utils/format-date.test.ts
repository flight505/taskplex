import { describe, it, expect } from "vitest";
import { formatDate, formatDateTime, formatRelative } from "../../src/utils/format-date.js";

describe("formatDate", () => {
  it("formats date as YYYY-MM-DD", () => {
    const date = new Date("2026-01-15T10:30:00Z");
    expect(formatDate(date)).toBe("2026-01-15");
  });
});

describe("formatDateTime", () => {
  it("formats date and time", () => {
    const date = new Date("2026-01-15T10:30:00Z");
    expect(formatDateTime(date)).toContain("2026-01-15");
    expect(formatDateTime(date)).toContain("10:30:00");
  });
});

describe("formatRelative", () => {
  it("shows seconds ago for recent dates", () => {
    const date = new Date(Date.now() - 30000);
    expect(formatRelative(date)).toMatch(/30s ago/);
  });

  it("shows minutes ago", () => {
    const date = new Date(Date.now() - 5 * 60 * 1000);
    expect(formatRelative(date)).toMatch(/5m ago/);
  });
});
