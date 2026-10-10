#!/usr/bin/env node
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const root = process.cwd();

function readJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch {
    return null;
  }
}

const packageJson = readJson(join(root, "package.json"));
const componentsJson = readJson(join(root, "components.json"));
const hasTailwindConfig =
  existsSync(join(root, "tailwind.config.ts")) ||
  existsSync(join(root, "tailwind.config.js")) ||
  existsSync(join(root, "tailwind.config.mjs"));
const hasAppDir = existsSync(join(root, "app")) || existsSync(join(root, "src", "app"));
const hasSrcDir = existsSync(join(root, "src"));
const hasAgentFrontend = existsSync(join(root, ".agents", "frontend"));

const deps = {
  ...(packageJson?.dependencies || {}),
  ...(packageJson?.devDependencies || {}),
};

const checks = [
  ["package.json", Boolean(packageJson)],
  ["TypeScript", Boolean(deps.typescript || existsSync(join(root, "tsconfig.json")))],
  ["Tailwind", Boolean(deps.tailwindcss || hasTailwindConfig)],
  ["shadcn components.json", Boolean(componentsJson)],
  ["lucide-react", Boolean(deps["lucide-react"])],
  ["MapLibre", Boolean(deps["maplibre-gl"])],
  ["Zustand", Boolean(deps.zustand)],
  ["React Hook Form", Boolean(deps["react-hook-form"])],
  ["Zod", Boolean(deps.zod)],
  ["TanStack Table", Boolean(deps["@tanstack/react-table"])],
  ["Playwright", Boolean(deps["@playwright/test"] || deps.playwright)],
  [".agents/frontend grounding", hasAgentFrontend],
  ["Next app directory", hasAppDir],
  ["src directory", hasSrcDir],
];

console.log("# Frontend Project Audit\n");
for (const [name, ok] of checks) {
  console.log(`- ${ok ? "OK" : "MISSING"}: ${name}`);
}

console.log("\n## Guidance");
if (!componentsJson) {
  console.log("- Initialize shadcn/ui before relying on registry blocks.");
}
if (!deps["lucide-react"]) {
  console.log("- Add lucide-react for consistent app icons.");
}
if (!hasAgentFrontend) {
  console.log("- Run scaffold.mjs to create .agents/frontend grounding docs.");
}
if (deps["maplibre-gl"]) {
  console.log("- Map app detected: keep map renderer separate from shadcn panels/controls.");
}
if (!deps["react-hook-form"] || !deps.zod) {
  console.log("- Do not add form libraries until real validation is needed.");
}
if (!deps["@tanstack/react-table"]) {
  console.log("- Do not add TanStack Table until tables require real sorting/filtering/pagination state.");
}
