import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function zeroPad3(n: number): string {
  return String(n).padStart(3, "0");
}

function ensureDir(dirPath: string): void {
  if (!fs.existsSync(dirPath)) {
    fs.mkdirSync(dirPath, { recursive: true });
  }
}

function buildMetadataObject(idStr: string) {
  const index = parseInt(idStr, 10) - 1;

  const backgrounds = [
    "Neon Grid",
    "Hologram",
    "Aurora",
    "Cyber City",
    "Quantum Field",
    "Stellar",
    "Matrix",
    "Synthwave",
    "Prism",
    "Voxel",
  ];

  const agentTypes = [
    "Research",
    "Trading",
    "Creator",
    "Analyst",
    "Explorer",
    "Guardian",
  ];

  const cores = ["EVM", "Solana", "L2", "Cosmos", "Bitcoin", "AIA"];
  const personalities = [
    "Curious",
    "Strategic",
    "Playful",
    "Stoic",
    "Adventurous",
    "Pragmatic",
  ];
  const badges = [
    "Genesis",
    "Pioneer",
    "Early Supporter",
    "Contributor",
    "Insider",
    "Trailblazer",
  ];

  const background = backgrounds[index % backgrounds.length];
  const agentType = agentTypes[index % agentTypes.length];
  const core = cores[index % cores.length];
  const personality = personalities[index % personalities.length];
  const badge = badges[index % badges.length];

  return {
    name: `AgentVault NFT #${idStr}`,
    description:
      "Mock metadata for the AgentVault collection. Replace placeholders before minting.",
    image: `https://placehold.co/600x600.png?text=AgentVault%20%23${idStr}`,
    external_url: `https://example.com/agentvault/${idStr}`,
    attributes: [
      { trait_type: "Background", value: background },
      { trait_type: "Agent Type", value: agentType },
      { trait_type: "Core", value: core },
      { trait_type: "Personality", value: personality },
      { trait_type: "Badge", value: badge },
      { display_type: "number", trait_type: "Generation", value: 1 },
    ],
  };
}

async function main(): Promise<void> {
  const projectRoot = path.resolve(__dirname, "..");
  const metadataDir = path.join(projectRoot, "metadata");
  ensureDir(metadataDir);

  const TOTAL = 250;
  let created = 0;
  let skipped = 0;

  for (let i = 1; i <= TOTAL; i++) {
    const idStr = zeroPad3(i);
    const filePath = path.join(metadataDir, `${idStr}.json`);
    const data = buildMetadataObject(idStr);

    if (fs.existsSync(filePath)) {
      skipped++;
      continue;
    }

    fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + "\n", "utf8");
    created++;
  }

  console.log(
    `Metadata generation complete. Created: ${created}, Skipped existing: ${skipped}, Target total: ${TOTAL}`
  );
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});


