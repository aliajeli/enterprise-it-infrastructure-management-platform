import { createInterface } from "node:readline/promises";
import { StringDecoder } from "node:string_decoder";
import { stdin, stdout } from "node:process";
import { prisma } from "@platform/database";
import {
  hashPassword,
  isValidPassword,
  normalizeUsername,
} from "../security/credentials.js";

function askText(question: string): Promise<string> {
  const terminal = createInterface({ input: stdin, output: stdout });
  return terminal.question(question).finally(() => terminal.close());
}

function askSecret(question: string): Promise<string> {
  if (!stdin.isTTY || typeof stdin.setRawMode !== "function") {
    return Promise.reject(
      new Error("Administrator bootstrap requires an interactive terminal."),
    );
  }

  return new Promise((resolve, reject) => {
    const decoder = new StringDecoder("utf8");
    let value = "";
    let settled = false;

    const restoreTerminal = () => {
      if (settled) return;
      settled = true;
      stdin.off("data", onData);
      stdin.setRawMode(false);
      stdin.pause();
      stdout.write("\n");
    };

    const onData = (chunk: Buffer) => {
      for (const character of decoder.write(chunk)) {
        if (character === "\u0003") {
          restoreTerminal();
          reject(new Error("Administrator bootstrap was cancelled."));
          return;
        }

        if (character === "\r" || character === "\n") {
          value += decoder.end();
          restoreTerminal();
          resolve(value);
          return;
        }

        if (character === "\u007f" || character === "\b") {
          const characters = Array.from(value);
          characters.pop();
          value = characters.join("");
          stdout.write("\b \b");
          continue;
        }

        if (character.charCodeAt(0) >= 32) {
          value += character;
          stdout.write("*");
        }
      }
    };

    stdout.write(question);
    stdin.setRawMode(true);
    stdin.resume();
    stdin.on("data", onData);
  });
}

async function main(): Promise<void> {
  let password = "";
  let confirmation = "";

  try {
    const usernameInput = await askText("Initial administrator username: ");
    const usernameNormalized = normalizeUsername(usernameInput);
    if (!usernameNormalized) {
      throw new Error(
        "Username must be 3–64 characters: letters, digits, dot, underscore or hyphen.",
      );
    }

    password = await askSecret("Administrator password: ");
    if (!isValidPassword(password)) {
      throw new Error(
        "Password must be 14–128 characters, at most 1,024 UTF-8 bytes, and contain no control characters.",
      );
    }

    confirmation = await askSecret("Confirm administrator password: ");
    if (password !== confirmation) {
      throw new Error("The passwords do not match.");
    }

    const passwordHash = await hashPassword(password);
    password = "";
    confirmation = "";

    const created = await prisma.$transaction(async (tx) => {
      await tx.$queryRaw`WITH advisory_lock AS MATERIALIZED (SELECT pg_advisory_xact_lock(735901224)) SELECT 1::int AS locked FROM advisory_lock`;

      const existingUsers = await tx.user.count();
      if (existingUsers !== 0) {
        throw new Error(
          "Bootstrap is disabled because at least one user already exists.",
        );
      }

      const user = await tx.user.create({
        data: {
          username: usernameInput.trim(),
          usernameNormalized,
          passwordHash,
          role: "ADMIN",
          status: "ACTIVE",
          passwordChangedAt: new Date(),
        },
      });

      await tx.auditEvent.create({
        data: {
          actorUserId: user.id,
          actorType: "SYSTEM",
          action: "AUTH_BOOTSTRAP_ADMIN",
          objectType: "user",
          objectId: user.id,
          outcome: "SUCCESS",
          metadata: { source: "local_interactive_cli" },
        },
      });

      return user;
    });

    stdout.write(
      `Initial administrator created successfully: ${created.username}\n`,
    );
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Administrator bootstrap failed.";
    process.stderr.write(`Bootstrap failed: ${message}\n`);
    process.exitCode = 1;
  } finally {
    password = "";
    confirmation = "";
    await prisma.$disconnect();
  }
}

void main();
