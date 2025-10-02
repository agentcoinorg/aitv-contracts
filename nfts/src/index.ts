import "dotenv/config";
import fs from "fs";
import path from "path";
import { parse as parseCsv } from "csv-parse/sync";
import { ethers } from "ethers";

type Recipient = {
  address: string;
  tokenId: bigint;
};

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value || value.trim() === "") {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

function parseRecipientsCsv(csvContent: string): Recipient[] {
  // First try parsing with headers
  let rows: any[] = parseCsv(csvContent, {
    columns: true,
    skip_empty_lines: true,
    trim: true,
  });

  const normalizeRow = (row: Record<string, unknown>): Recipient => {
    const keys = Object.keys(row);
    const addressKey = keys.find((k) => k.toLowerCase() === "address");
    const tokenKey =
      keys.find((k) => k.toLowerCase() === "tokenid") ??
      keys.find((k) => k.toLowerCase() === "id") ??
      "tokenId";

    if (!addressKey || !(addressKey in row)) {
      throw new Error("CSV must include an 'address' column (or provide no header)");
    }

    const addressRaw = String(row[addressKey] ?? "").trim();
    const tokenRaw = String((row as any)[tokenKey] ?? "").trim();

    if (!ethers.isAddress(addressRaw)) {
      throw new Error(`Invalid address in CSV: ${addressRaw}`);
    }

    if (tokenRaw === "") {
      throw new Error(`Missing token id for address ${addressRaw}`);
    }

    let tokenId: bigint;
    try {
      // Support decimal or hex
      tokenId = tokenRaw.startsWith("0x") ? BigInt(tokenRaw) : BigInt(parseInt(tokenRaw, 10));
    } catch (e) {
      throw new Error(`Invalid token id '${tokenRaw}' for ${addressRaw}`);
    }

    return { address: ethers.getAddress(addressRaw), tokenId };
  };

  try {
    if (rows.length > 0 && Object.keys(rows[0]).some((k) => k.toLowerCase() === "address")) {
      return rows.map((r) => normalizeRow(r));
    }
  } catch (_) {
    // fall through and try without headers
  }

  // Fallback: parse without headers, expect exactly two columns: address, tokenId
  const rowsNoHeader: any[] = parseCsv(csvContent, {
    columns: false,
    skip_empty_lines: true,
    trim: true,
  });

  return rowsNoHeader.map((cols, idx) => {
    if (!Array.isArray(cols) || cols.length < 2) {
      throw new Error(`CSV row ${idx + 1} must have at least 2 columns: address, tokenId`);
    }
    const [addressRaw, tokenRaw] = [String(cols[0]).trim(), String(cols[1]).trim()];
    if (!ethers.isAddress(addressRaw)) {
      throw new Error(`Invalid address in CSV at row ${idx + 1}: ${addressRaw}`);
    }
    if (tokenRaw === "") {
      throw new Error(`Missing token id in CSV at row ${idx + 1}`);
    }
    const tokenId = tokenRaw.startsWith("0x") ? BigInt(tokenRaw) : BigInt(parseInt(tokenRaw, 10));
    return { address: ethers.getAddress(addressRaw), tokenId };
  });
}

async function main(): Promise<void> {
  const rpcUrl = requireEnv("RPC_URL");
  const privateKey = requireEnv("PRIVATE_KEY");
  const nftAddressRaw = requireEnv("NFT_CONTRACT_ADDRESS");
  if (!ethers.isAddress(nftAddressRaw)) {
    throw new Error(`Invalid NFT_CONTRACT_ADDRESS: ${nftAddressRaw}`);
  }

  const multisendAddressRaw = requireEnv("MULTISEND_CONTRACT_ADDRESS");
  if (!ethers.isAddress(multisendAddressRaw)) {
    throw new Error(`Invalid MULTISEND_CONTRACT_ADDRESS: ${multisendAddressRaw}`);
  }

  const confirmations = parseInt(process.env.CONFIRMATIONS ?? "1", 10);
  const dryRun = (process.env.DRY_RUN ?? "false").toLowerCase() === "true";
  const pauseMs = parseInt(process.env.PAUSE_MS ?? "0", 10);
  const batchSize = parseInt(process.env.BATCH_SIZE ?? "50", 10);
  if (!Number.isFinite(batchSize) || batchSize < 1) {
    throw new Error("BATCH_SIZE must be a positive integer");
  }

  const csvPath = path.resolve(
    process.cwd(),
    process.env.CSV_PATH ?? process.argv[2] ?? "recipients.csv"
  );

  if (!fs.existsSync(csvPath)) {
    throw new Error(`CSV file not found at: ${csvPath}`);
  }

  const csvContent = fs.readFileSync(csvPath, "utf8");
  const recipients = parseRecipientsCsv(csvContent);

  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const wallet = new ethers.Wallet(privateKey, provider);
  const fromAddress = await wallet.getAddress();
  const nftAddress = ethers.getAddress(nftAddressRaw);
  const multisendAddress = ethers.getAddress(multisendAddressRaw);

  const ERC721_ABI = [
    "function ownerOf(uint256 tokenId) view returns (address)",
    "function safeTransferFrom(address from, address to, uint256 tokenId)",
    "function isApprovedForAll(address owner, address operator) view returns (bool)",
    "function setApprovalForAll(address operator, bool approved)",
  ];

  const MULTISEND_ABI = [
    "function multisend(address _collection, uint256[] _tokenIds, address[] _recipients)",
  ];

  const nft = new ethers.Contract(nftAddress, ERC721_ABI, wallet);
  const multisend = new ethers.Contract(multisendAddress, MULTISEND_ABI, wallet);

  console.log(`Loaded ${recipients.length} recipient(s) from ${path.basename(csvPath)}`);
  console.log(`From:      ${fromAddress}`);
  console.log(`NFT:       ${nftAddress}`);
  console.log(`Multisend: ${multisendAddress}`);
  console.log(`Batch size: ${batchSize}`);
  if (dryRun) {
    console.log("DRY_RUN is enabled. No transactions will be sent.");
  }

  let approvalSetByScript = false;
  try {
    const alreadyApproved: boolean = await nft.isApprovedForAll(
      fromAddress,
      multisendAddress
    );
    if (!alreadyApproved) {
      console.log(
        `Granting setApprovalForAll to operator ${multisendAddress} on ${nftAddress}`
      );
      if (!dryRun) {
        const approveTx = await nft.setApprovalForAll(multisendAddress, true);
        console.log(`Approval tx: ${approveTx.hash}`);
        const approveReceipt = await approveTx.wait(confirmations);
        console.log(
          `Approval confirmed in block ${approveReceipt.blockNumber} (status=${approveReceipt.status})`
        );
        approvalSetByScript = true;
      } else {
        console.log("DRY_RUN: would call setApprovalForAll(..., true)");
      }
    } else {
      console.log(`Already approved for operator ${multisendAddress}`);
    }

    const validTransfers: Recipient[] = [];
    for (let i = 0; i < recipients.length; i++) {
      const { address: to, tokenId } = recipients[i];
      const ordinal = `#${i + 1}/${recipients.length}`;
      try {
        const currentOwner: string = await nft.ownerOf(tokenId);
        if (ethers.getAddress(currentOwner) !== fromAddress) {
          console.warn(
            `${ordinal} Skipping token ${tokenId.toString()} → ${to}: Not owner (current owner: ${currentOwner})`
          );
          continue;
        }
        validTransfers.push({ address: to, tokenId });
      } catch (err) {
        console.error(
          `${ordinal} Error checking owner for token ${tokenId.toString()}:`,
          err
        );
      }
    }

    console.log(
      `Prepared ${validTransfers.length} transfer(s) out of ${recipients.length}`
    );

    const totalBatches = Math.ceil(validTransfers.length / batchSize) || 0;
    for (let start = 0, batchIndex = 0; start < validTransfers.length; start += batchSize, batchIndex++) {
      const end = Math.min(start + batchSize, validTransfers.length);
      const batch = validTransfers.slice(start, end);
      const tokenIds = batch.map((r) => r.tokenId);
      const tos = batch.map((r) => r.address);
      const ordinal = `Batch ${batchIndex + 1}/${totalBatches}`;

      console.log(`${ordinal} Sending ${tokenIds.length} token(s) via multisend`);
      if (dryRun) {
        continue;
      }

      try {
        const tx = await multisend.multisend(nftAddress, tokenIds, tos);
        console.log(`${ordinal} Submitted tx: ${tx.hash}`);
        const receipt = await tx.wait(confirmations);
        console.log(
          `${ordinal} Confirmed in block ${receipt.blockNumber} (status=${receipt.status})`
        );
      } catch (err) {
        console.error(`${ordinal} Error in multisend:`, err);
      }

      if (pauseMs > 0 && end < validTransfers.length) {
        await new Promise((resolve) => setTimeout(resolve, pauseMs));
      }
    }
  } finally {
    if (approvalSetByScript) {
      console.log(
        `Revoking setApprovalForAll from operator ${multisendAddress} on ${nftAddress}`
      );
      if (!dryRun) {
        try {
          const revokeTx = await nft.setApprovalForAll(multisendAddress, false);
          console.log(`Revoke tx: ${revokeTx.hash}`);
          const revokeReceipt = await revokeTx.wait(confirmations);
          console.log(
            `Revoke confirmed in block ${revokeReceipt.blockNumber} (status=${revokeReceipt.status})`
          );
        } catch (err) {
          console.error("Error revoking approval:", err);
        }
      } else {
        console.log("DRY_RUN: would call setApprovalForAll(..., false)");
      }
    }
  }
}

main().catch((error: unknown) => {
  console.error(error);
  process.exit(1);
});
