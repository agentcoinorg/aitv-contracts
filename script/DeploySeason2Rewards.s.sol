// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AITVERC721Base} from "../src/AITVERC721Base.sol";
import {AITVSeasonRewardsBatchDeployer} from "../src/AITVSeasonRewardsBatchDeployer.sol";

contract DeploySeason2RewardsScript is Script {
    function run() public {
        string memory baseURI = vm.envString("S2R_BASE_URI");
        address owner = vm.envAddress("S2R_OWNER");
        address recipient = vm.envAddress("S2R_MINT_RECIPIENT");
        uint256 totalToMint = vm.envUint("S2R_TOTAL");
        uint256 batchSize = vm.envUint("S2R_BATCH_SIZE");

        vm.startBroadcast();
        AITVSeasonRewardsBatchDeployer deployer = new AITVSeasonRewardsBatchDeployer(
            "AITV Season 2 Badges",
            "AITVS2B",
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
        console.log("AITV Season 2 Badges deployed at %s", address(nft));
        console.log("Minted %s tokens to %s across multiple transactions", totalMinted, recipient);
    }

}


