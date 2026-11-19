import type { FastifyReply } from "fastify";
import type { ApiConfig } from "../config.js";

const SESSION_COOKIE_PRODUCTION = "__Host-platform_session";
const SESSION_COOKIE_DEVELOPMENT = "platform_session";

export function sessionCookieName(config: ApiConfig): string {
  return config.cookieSecure
    ? SESSION_COOKIE_PRODUCTION
    : SESSION_COOKIE_DEVELOPMENT;
}

export function setSessionCookie(
  reply: FastifyReply,
  config: ApiConfig,
  token: string,
  expiresAt: Date,
): void {
  reply.setCookie(sessionCookieName(config), token, {
    httpOnly: true,
    secure: config.cookieSecure,
    sameSite: "lax",
    path: "/",
    expires: expiresAt,
    maxAge: config.sessionTtlSeconds,
  });
}

export function clearSessionCookie(
  reply: FastifyReply,
  config: ApiConfig,
): void {
  reply.clearCookie(sessionCookieName(config), {
    httpOnly: true,
    secure: config.cookieSecure,
    sameSite: "lax",
    path: "/",
  });
}
