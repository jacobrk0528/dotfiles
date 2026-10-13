// Load artoo's keys from the shared ~/dotfiles/.env (one level above this project) no matter
// where artoo is run from. Real environment variables win.
//
// Only artoo's own keys are taken. That file also holds unrelated secrets (Home Assistant,
// NetSuite, ...) and artoo runs LLM-chosen shell commands, so they must never enter this
// process's environment.
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const OWN = /^(TYPESAFE_|OPENAI_|JEV_)/;

const file = process.env.DOTFILES_ENV ?? join(import.meta.dir, "..", "..", ".env");
if (existsSync(file)) {
  for (const line of readFileSync(file, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/);
    if (m && OWN.test(m[1]!) && !process.env[m[1]!]) process.env[m[1]!] = m[2]!.replace(/^(['"])(.*)\1$/, "$2");
  }
}
