export const MIN_LEASE_MS = 5_000;
export const MAX_LEASE_MS = 300_000;
export const DEFAULT_LEASE_MS = 30_000;
export const MAX_RETRY_DELAY_MS = 300_000;

export function retryDelayMs(attemptCount: number): number {
  if (!Number.isInteger(attemptCount) || attemptCount < 1) {
    throw new Error("Attempt count must be a positive integer.");
  }
  return Math.min(MAX_RETRY_DELAY_MS, 5_000 * 2 ** Math.min(attemptCount - 1, 16));
}

export function canRetry(attemptCount: number, maxAttempts: number): boolean {
  return Number.isInteger(attemptCount) &&
    Number.isInteger(maxAttempts) &&
    attemptCount >= 0 &&
    maxAttempts >= 1 &&
    attemptCount < maxAttempts;
}
