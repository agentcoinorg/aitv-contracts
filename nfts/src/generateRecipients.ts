import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function zeroPad3(n: number): string {
  return String(n).padStart(3, "0");
}

function ensureFileDir(filePath: string): void {
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
}

function addressForId(id: number): string {
  // Deterministic, predictable address based on id. Matches the example pattern.
  const hex = id.toString(16).padStart(40, "0");
  return "0x" + hex;
}

async function main(): Promise<void> {
  const projectRoot = path.resolve(__dirname, "..");
  const csvPath = path.join(projectRoot, "recipients.csv");

  const TOTAL = 250;
  const lines: string[] = ["address,tokenId"]; // always overwrite with header

  for (let i = 1; i <= TOTAL; i++) {
    const address = addressForId(i);
    const tokenId = zeroPad3(i).replace(/^0+/, "") || "0"; // no leading zeros in CSV
    lines.push(`${address},${tokenId}`);
  }

  ensureFileDir(csvPath);
  fs.writeFileSync(csvPath, lines.join("\n") + "\n", "utf8");
  console.log(`Wrote ${TOTAL} recipients to ${path.basename(csvPath)}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
