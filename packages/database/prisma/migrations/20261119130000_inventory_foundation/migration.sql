CREATE TYPE "asset_kind" AS ENUM ('COMPUTER', 'SERVER', 'SWITCH', 'ROUTER', 'FIREWALL', 'NVR', 'CAMERA', 'PRINTER', 'POS', 'UPS', 'OTHER');
CREATE TYPE "asset_status" AS ENUM ('ACTIVE', 'INACTIVE', 'RETIRED');
CREATE TYPE "discovery_source" AS ENUM ('MANUAL', 'SNMP', 'SSH', 'AGENT', 'ISAPI', 'IMPORT');
CREATE TYPE "discovery_status" AS ENUM ('QUEUED', 'RUNNING', 'SUCCEEDED', 'PARTIAL', 'FAILED', 'CANCELLED');
CREATE TYPE "port_state" AS ENUM ('UNKNOWN', 'UP', 'DOWN');

CREATE TABLE "assets" (
  "id" UUID NOT NULL,
  "branch_id" UUID NOT NULL,
  "asset_code" VARCHAR(64) NOT NULL,
  "name" VARCHAR(160) NOT NULL,
  "kind" "asset_kind" NOT NULL,
  "status" "asset_status" NOT NULL DEFAULT 'ACTIVE',
  "hostname" VARCHAR(255),
  "primary_ip" INET,
  "mac_address" VARCHAR(17),
  "vendor" VARCHAR(120),
  "model" VARCHAR(120),
  "serial_number" VARCHAR(160),
  "location" VARCHAR(255),
  "description" VARCHAR(2000),
  "version" INTEGER NOT NULL DEFAULT 1,
  "deleted_at" TIMESTAMPTZ(6),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "assets_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "assets_mac_address_format_check" CHECK ("mac_address" IS NULL OR "mac_address" ~* '^([0-9a-f]{2}:){5}[0-9a-f]{2}$')
);
CREATE UNIQUE INDEX "assets_branch_id_asset_code_key" ON "assets"("branch_id", "asset_code");
CREATE INDEX "assets_branch_id_kind_status_deleted_at_idx" ON "assets"("branch_id", "kind", "status", "deleted_at");
CREATE INDEX "assets_primary_ip_idx" ON "assets"("primary_ip");
CREATE INDEX "assets_serial_number_idx" ON "assets"("serial_number");

CREATE TABLE "switch_profiles" (
  "id" UUID NOT NULL,
  "asset_id" UUID NOT NULL,
  "sys_name" VARCHAR(255),
  "sys_descr" VARCHAR(1000),
  "sys_object_id" VARCHAR(255),
  "firmware_version" VARCHAR(160),
  "reported_port_count" INTEGER,
  "last_discovery_at" TIMESTAMPTZ(6),
  "last_discovery_status" "discovery_status",
  CONSTRAINT "switch_profiles_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "switch_profiles_reported_port_count_check" CHECK ("reported_port_count" IS NULL OR "reported_port_count" >= 0)
);
CREATE UNIQUE INDEX "switch_profiles_asset_id_key" ON "switch_profiles"("asset_id");

CREATE TABLE "switch_ports" (
  "id" UUID NOT NULL,
  "switch_id" UUID NOT NULL,
  "if_index" INTEGER NOT NULL,
  "name" VARCHAR(160),
  "alias" VARCHAR(160),
  "description" VARCHAR(1000),
  "configured_vlan_id" INTEGER,
  "configured_tagged_vlans" INTEGER[] NOT NULL DEFAULT ARRAY[]::INTEGER[],
  "connected_device_label" VARCHAR(255),
  "version" INTEGER NOT NULL DEFAULT 1,
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMPTZ(6) NOT NULL,
  CONSTRAINT "switch_ports_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "switch_ports_if_index_check" CHECK ("if_index" > 0),
  CONSTRAINT "switch_ports_vlan_id_check" CHECK ("configured_vlan_id" IS NULL OR "configured_vlan_id" BETWEEN 1 AND 4094),
  CONSTRAINT "switch_ports_tagged_vlans_check" CHECK (array_position("configured_tagged_vlans", 0) IS NULL AND NOT EXISTS (SELECT 1 FROM unnest("configured_tagged_vlans") AS vlan WHERE vlan < 1 OR vlan > 4094))
);
CREATE UNIQUE INDEX "switch_ports_switch_id_if_index_key" ON "switch_ports"("switch_id", "if_index");
CREATE INDEX "switch_ports_switch_id_name_idx" ON "switch_ports"("switch_id", "name");

CREATE TABLE "port_observations" (
  "id" UUID NOT NULL,
  "port_id" UUID NOT NULL,
  "source" "discovery_source" NOT NULL,
  "observed_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "admin_state" "port_state" NOT NULL DEFAULT 'UNKNOWN',
  "oper_state" "port_state" NOT NULL DEFAULT 'UNKNOWN',
  "vlan_id" INTEGER,
  "ip_address" INET,
  "mac_address" VARCHAR(17),
  "speed_mbps" INTEGER,
  "raw_metadata" JSONB,
  CONSTRAINT "port_observations_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "port_observations_vlan_id_check" CHECK ("vlan_id" IS NULL OR "vlan_id" BETWEEN 1 AND 4094),
  CONSTRAINT "port_observations_speed_check" CHECK ("speed_mbps" IS NULL OR "speed_mbps" > 0),
  CONSTRAINT "port_observations_mac_format_check" CHECK ("mac_address" IS NULL OR "mac_address" ~* '^([0-9a-f]{2}:){5}[0-9a-f]{2}$')
);
CREATE INDEX "port_observations_port_id_observed_at_idx" ON "port_observations"("port_id", "observed_at" DESC);
CREATE INDEX "port_observations_observed_at_idx" ON "port_observations"("observed_at" DESC);

CREATE TABLE "discovery_runs" (
  "id" UUID NOT NULL,
  "branch_id" UUID NOT NULL,
  "target_asset_id" UUID,
  "initiated_by_user_id" UUID,
  "source" "discovery_source" NOT NULL,
  "status" "discovery_status" NOT NULL DEFAULT 'QUEUED',
  "started_at" TIMESTAMPTZ(6),
  "completed_at" TIMESTAMPTZ(6),
  "discovered_assets" INTEGER NOT NULL DEFAULT 0,
  "updated_assets" INTEGER NOT NULL DEFAULT 0,
  "unchanged_assets" INTEGER NOT NULL DEFAULT 0,
  "failed_items" INTEGER NOT NULL DEFAULT 0,
  "error_code" VARCHAR(100),
  "error_message" VARCHAR(1000),
  "created_at" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "discovery_runs_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "discovery_runs_counts_check" CHECK ("discovered_assets" >= 0 AND "updated_assets" >= 0 AND "unchanged_assets" >= 0 AND "failed_items" >= 0),
  CONSTRAINT "discovery_runs_time_check" CHECK ("completed_at" IS NULL OR "started_at" IS NULL OR "completed_at" >= "started_at")
);
CREATE INDEX "discovery_runs_branch_id_created_at_idx" ON "discovery_runs"("branch_id", "created_at" DESC);
CREATE INDEX "discovery_runs_status_created_at_idx" ON "discovery_runs"("status", "created_at");

ALTER TABLE "assets" ADD CONSTRAINT "assets_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "switch_profiles" ADD CONSTRAINT "switch_profiles_asset_id_fkey" FOREIGN KEY ("asset_id") REFERENCES "assets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "switch_ports" ADD CONSTRAINT "switch_ports_switch_id_fkey" FOREIGN KEY ("switch_id") REFERENCES "switch_profiles"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "port_observations" ADD CONSTRAINT "port_observations_port_id_fkey" FOREIGN KEY ("port_id") REFERENCES "switch_ports"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "discovery_runs" ADD CONSTRAINT "discovery_runs_branch_id_fkey" FOREIGN KEY ("branch_id") REFERENCES "branches"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "discovery_runs" ADD CONSTRAINT "discovery_runs_target_asset_id_fkey" FOREIGN KEY ("target_asset_id") REFERENCES "assets"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "discovery_runs" ADD CONSTRAINT "discovery_runs_initiated_by_user_id_fkey" FOREIGN KEY ("initiated_by_user_id") REFERENCES "users"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
