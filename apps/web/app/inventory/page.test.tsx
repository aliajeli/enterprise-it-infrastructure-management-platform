import type { ReactNode } from "react";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";

vi.mock("../components/auth-guard", () => ({
  AuthGuard: ({ children }: { children: ReactNode }) => children,
}));
vi.mock("../components/logout-button", () => ({
  LogoutButton: () => null,
}));

import InventoryPage from "./page";

describe("inventory workspace", () => {
  it("describes the read-only switch-port observation history workflow", () => {
    const markup = renderToStaticMarkup(createElement(InventoryPage));
    expect(markup).toContain("Branch equipment");
    expect(markup).toContain("Switch-port observation history is available from each port");
    expect(markup).toContain("opening it never triggers a device poll");
  });
});
