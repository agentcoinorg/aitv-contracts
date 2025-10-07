// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AITVERC721Base} from "../src/AITVERC721Base.sol";
import {AITVSeason1RewardsBatchDeployer} from "../src/AITVSeason1RewardsBatchDeployer.sol";

contract DeploySeason1RewardsScript is Script {
    function run() public {
        string memory baseURI = vm.envString("S1R_BASE_URI");
        address owner = vm.envAddress("S1R_OWNER");
        address recipient = vm.envAddress("S1R_MINT_RECIPIENT");
        uint256 totalToMint = vm.envUint("S1R_TOTAL");
        uint256 batchSize = vm.envUint("S1R_BATCH_SIZE");

        vm.startBroadcast();
        AITVSeason1RewardsBatchDeployer deployer = new AITVSeason1RewardsBatchDeployer(
            "AITV Season 1 Badges",
            "AITVS1B",
            baseURI,
            recipient,
            owner,
            totalToMint
        );

        uint256 totalMinted;
        while (true) {
            uint256 minted = deployer.mintNextBatch(batchSize);
            if (minted == 0) {
                break;
            }
            totalMinted += minted;
            console.log("Minted batch: %s tokens (total %s / %s)", minted, totalMinted, totalToMint);
        }

        deployer.finalize();
        vm.stopBroadcast();

        AITVERC721Base nft = deployer.nft();
        console.log("Batch deployer deployed at %s", address(deployer));
        console.log("AITV Season 1 Badges deployed at %s", address(nft));
        console.log("Minted %s tokens to %s across multiple transactions", totalMinted, recipient);
    }

}


