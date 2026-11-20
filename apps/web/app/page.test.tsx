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
    expect(markup).toContain("Manage branches in User management");
    expect(markup).toContain("Browse registered assets in Device inventory");
    expect(markup).toContain("Agent service not deployed");
    expect(markup).toContain("Monitoring not configured");
    expect(markup).toContain("Status reflects implementation, not simulated health.");
  });

  it("reports implemented foundations accurately without implying production readiness", () => {
    const markup = renderToStaticMarkup(createElement(DashboardPage));

    expect(markup).toContain("Authentication, users, branches and inventory APIs");
    expect(markup).toContain("Implemented");
    expect(markup).toContain("Foundation only");
    expect(markup).toContain("Local preview");
    expect(markup).toContain("Not configured");
    expect(markup).toContain("Local preview v0.1.39");
  });

  it("exposes a real Overview link and marks planned modules as unavailable", () => {
    const markup = renderToStaticMarkup(createElement(DashboardPage));

    expect(markup).toContain('href="/"');
    expect(markup).toContain('aria-current="page"');
    expect(markup).toContain('aria-disabled="true"');
    expect(markup).toContain("Mobile navigation");
  });
});
