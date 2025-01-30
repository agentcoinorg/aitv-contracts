import * as ethers from "ethers";
import fs from "fs";
import dotenv from "dotenv";

dotenv.config();

const AIRDROP_CONTRACT_ADDRESS = process.env.AIRDROP_CONTRACT_ADDRESS;
const ALCHEMY_API_KEY = process.env.ALCHEMY_API_KEY;
const WALLET_PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY;

if (!AIRDROP_CONTRACT_ADDRESS) {
  throw new Error('AIRDROP_CONTRACT_ADDRESS is required');
}
if (!ALCHEMY_API_KEY) {
  throw new Error('ALCHEMY_API_KEY is required');
}
if (!WALLET_PRIVATE_KEY) {
  throw new Error('WALLET_PRIVATE_KEY is required');
}

const BATCH_SIZE = process.env.BATCH_SIZE 
  ? parseInt(process.env.BATCH_SIZE)
  : 100;

const provider = new ethers.JsonRpcProvider(`https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}`);

const contractABI = [
  'function multiClaim(address[] recipients) external'
];

const contract = new ethers.Contract(AIRDROP_CONTRACT_ADDRESS, contractABI, provider);

function getTokenHolders() {
  const text = fs.readFileSync('holders.txt', 'utf-8');
  const addresses = text.split('\n').map((holder) => holder.trim());

  for (const address of addresses) {
    if (!ethers.isAddress(address)) {
      throw new Error(`Invalid address: ${address}`);
    }
  }

  return addresses;
}

async function multiClaimForBatch(addresses) {
  const wallet = new ethers.Wallet(WALLET_PRIVATE_KEY, provider);

  const contractWithSigner = contract.connect(wallet);

  try {
    console.log(`Claiming for batch of ${addresses.length} addresses...`);
    const tx = await contractWithSigner.multiClaim(addresses);
    await tx.wait(1);
    console.log('Batch claim successful:', tx.hash);
  } catch (error) {
    console.error('Error claiming for batch:', error);
  }
}

async function processClaims() {
  const holders = getTokenHolders();

  if (holders.length === 0) {
    console.log('No token holders found.');
    return;
  }

  let batch = [];
  for (let i = 0; i < holders.length; i++) {
    const holder = holders[i];
    batch.push(holder);

    if (batch.length === BATCH_SIZE || i === holders.length - 1) {
      await multiClaimForBatch(batch);
      batch = [];
    }
  }

  console.log('All claims processed.');
}

processClaims().catch(console.error).then(() => process.exit(0));