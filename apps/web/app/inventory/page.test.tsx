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

import InventoryPage, { buildInventoryCsv } from "./page";

describe("inventory workspace", () => {
  it("exports CSV with quoted fields and neutralizes spreadsheet formulas", () => {
    const csv = buildInventoryCsv([{
      id: "asset-1",
      branchId: "branch-1",
      assetCode: "QA-001",
      name: 'Front desk, "POS"',
      kind: "COMPUTER",
      status: "ACTIVE",
      hostname: '=HYPERLINK("https://example.invalid")',
      primaryIp: "192.0.2.10",
      macAddress: null,
      vendor: "Example",
      model: "Model X",
      location: "Store 01",
      description: "Line one\nLine two",
      version: 3,
      switch: null,
    }], "QA");

    expect(csv.startsWith("\uFEFF")).toBe(true);
    expect(csv).toContain('"Front desk, ""POS"""');
    expect(csv).toContain('"\'=HYPERLINK(""https://example.invalid"")"');
    expect(csv).toContain('"Line one\nLine two"');
  });

  it("describes the read-only switch-port observation history workflow", () => {
    const markup = renderToStaticMarkup(createElement(InventoryPage));
    expect(markup).toContain("Branch equipment");
    expect(markup).toContain("Switch-port observation history is available from each port");
    expect(markup).toContain("opening it never triggers a device poll");
  });
});
