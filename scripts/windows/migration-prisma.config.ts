// Deployment tooling configuration only. No credentials are stored here.
// Actual Windows migrations remain disabled until the credential and cluster
// ownership gates are implemented, reviewed, and accepted.
import { defineConfig, env } from "prisma/config";

export default defineConfig({
  schema: "../packages/database/prisma/schema.prisma",
  migrations: { path: "../packages/database/prisma/migrations" },
  datasource: { url: env("DATABASE_URL") },
});
