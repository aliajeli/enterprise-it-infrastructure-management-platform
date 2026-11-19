export interface ApiConfig {
  host: string;
  port: number;
  publicOrigin: string;
  cookieSecure: boolean;
  sessionTtlSeconds: number;
  loginLockoutThreshold: number;
  loginLockoutMs: number;
}

export function loadApiConfig(
  environment: NodeJS.ProcessEnv = process.env,
): ApiConfig {
  const port = Number(environment.API_PORT ?? "13001");
  if (!Number.isInteger(port) || port < 1 || port > 65_535) {
    throw new Error("API_PORT must be an integer between 1 and 65535.");
  }

  let publicOrigin: string;
  try {
    publicOrigin = new URL(
      environment.PUBLIC_ORIGIN ?? "http://127.0.0.1:3000",
    ).origin;
  } catch {
    throw new Error("PUBLIC_ORIGIN must be a valid absolute URL.");
  }

  const cookieSecure =
    environment.COOKIE_SECURE === undefined
      ? environment.NODE_ENV === "production"
      : environment.COOKIE_SECURE === "true";

  return {
    host: environment.API_HOST ?? "127.0.0.1",
    port,
    publicOrigin,
    cookieSecure,
    sessionTtlSeconds: 12 * 60 * 60,
    loginLockoutThreshold: 5,
    loginLockoutMs: 15 * 60 * 1000,
  };
}
