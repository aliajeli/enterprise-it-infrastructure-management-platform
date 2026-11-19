import type { ReactNode } from "react";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("./components/auth-guard", () => ({
  AuthGuard: ({ children }: { children: ReactNode }) => children,
}));
vi.mock("./components/logout-button", () => ({
  LogoutButton: () => null,
}));

import DashboardPage from "./page";

describe("infrastructure dashboard foundation", () => {
  it("shows explicit empty states instead of invented operational data", () => {
    const markup = renderToStaticMarkup(createElement(DashboardPage));

    expect(markup).toContain("No infrastructure data available");
    expect(markup).toContain("No branch records yet");
    expect(markup).toContain("Inventory not connected");
    expect(markup).toContain("Agent service not deployed");
    expect(markup).toContain("Monitoring not configured");
    expect(markup).toContain("Status reflects implementation, not simulated health.");
  });

  it("exposes a real Overview link and marks planned modules as unavailable", () => {
    const markup = renderToStaticMarkup(createElement(DashboardPage));

    expect(markup).toContain('href="/"');
    expect(markup).toContain('aria-current="page"');
    expect(markup).toContain('aria-disabled="true"');
    expect(markup).toContain("Mobile navigation");
  });
});
