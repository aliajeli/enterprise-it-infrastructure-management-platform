import { describe, expect, it } from "vitest";
import { canRetry, retryDelayMs } from "./policy.js";

describe("discovery worker retry policy", () => {
  it("uses bounded exponential backoff", () => {
    expect(retryDelayMs(1)).toBe(5_000);
    expect(retryDelayMs(2)).toBe(10_000);
    expect(retryDelayMs(3)).toBe(20_000);
    expect(retryDelayMs(20)).toBe(300_000);
  });

  it("rejects invalid attempt counts", () => {
    expect(() => retryDelayMs(0)).toThrow();
    expect(() => retryDelayMs(1.5)).toThrow();
  });

  it("allows retries only below the configured maximum", () => {
    expect(canRetry(0, 3)).toBe(true);
    expect(canRetry(2, 3)).toBe(true);
    expect(canRetry(3, 3)).toBe(false);
    expect(canRetry(-1, 3)).toBe(false);
  });
});
