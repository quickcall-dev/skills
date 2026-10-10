#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const catalogPath = join(here, "..", "references", "oss-provider-catalog.json");
const catalog = JSON.parse(readFileSync(catalogPath, "utf8"));

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const item = process.argv[i];
  if (item.startsWith("--")) {
    const key = item.slice(2);
    const next = process.argv[i + 1];
    if (next && !next.startsWith("--")) {
      args.set(key, next);
      i += 1;
    } else {
      args.set(key, "true");
    }
  }
}

const requested = (args.get("surface") || "sidebar,chat,dashboard")
  .split(",")
  .map((item) => item.trim())
  .filter(Boolean);

const providersByName = new Map(catalog.providers.map((provider) => [provider.name, provider]));

console.log("# Open-Source Frontend Surface Plan\n");
console.log(`Policy: ${catalog.policy.default}`);
console.log(`Customization: ${catalog.policy.theme_model}\n`);

for (const surface of requested) {
  const providerNames = catalog.surfaces[surface];
  if (!providerNames) {
    console.log(`## ${surface}`);
    console.log("- No predefined plan. Compose from shadcn/ui primitives and add to the private registry if reused.\n");
    continue;
  }

  console.log(`## ${surface}`);
  for (const name of providerNames) {
    if (name === "private registry") {
      console.log("- Private registry: use or create a house block if this pattern repeats.");
      continue;
    }
    if (name === "MapLibre GL JS") {
      console.log("- MapLibre GL JS: use only for real map/canvas/vector-layer surfaces.");
      continue;
    }
    if (name === "shadcn/ui panels" || name === "shadcn/ui primitives" || name === "shadcn/ui official primitives") {
      console.log(`- ${name}: compose from source-owned shadcn components.`);
      continue;
    }

    const provider = providersByName.get(name);
    if (!provider) {
      console.log(`- ${name}: verify source/license before use.`);
      continue;
    }
    console.log(`- ${provider.name}: ${provider.url}`);
    console.log(`  - Best for: ${provider.best_for.join(", ")}`);
    console.log(`  - Install model: ${provider.install_model}`);
    console.log(`  - Customization: ${provider.customization}`);
  }
  console.log("");
}

console.log("Next step: install/copy one OSS block, remove demo cruft, then promote reusable patterns into your private registry.");
