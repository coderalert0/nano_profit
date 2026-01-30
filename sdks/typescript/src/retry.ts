export interface RetryOptions {
  maxRetries: number;
}

/** Status codes that should never be retried. */
const NON_RETRYABLE_STATUSES = new Set([401, 422]);

function isRetryableError(error: unknown): boolean {
  if (error instanceof Response) {
    if (NON_RETRYABLE_STATUSES.has(error.status)) return false;
    return error.status >= 500;
  }
  // Network errors, timeouts, etc. are retryable
  return true;
}

function backoffMs(attempt: number): number {
  const base = Math.min(1000 * Math.pow(2, attempt), 30_000);
  const jitter = Math.random() * base * 0.5;
  return base + jitter;
}

/**
 * Execute `fn` with exponential backoff retry.
 *
 * - Up to `maxRetries` additional attempts after the first failure.
 * - Delay: min(1s * 2^attempt, 30s) + jitter.
 * - Retries on 5xx and network errors.
 * - Drops immediately on 401 / 422.
 */
export async function withRetry<T>(
  fn: () => Promise<T>,
  options: RetryOptions,
): Promise<T> {
  let lastError: unknown;

  for (let attempt = 0; attempt <= options.maxRetries; attempt++) {
    try {
      return await fn();
    } catch (error: unknown) {
      lastError = error;

      if (!isRetryableError(error)) {
        throw error;
      }

      if (attempt < options.maxRetries) {
        const delay = backoffMs(attempt);
        await new Promise((resolve) => setTimeout(resolve, delay));
      }
    }
  }

  throw lastError;
}
