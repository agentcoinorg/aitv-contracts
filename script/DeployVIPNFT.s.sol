// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AITVERC721MintableBase} from "../src/AITVERC721MintableBase.sol";

// VIP NFT deployment script
contract DeployVIPNFTScript is Script {
    function run() public {
        // VIP-specific env vars
        string memory name = "Test VIP NFT";
        string memory symbol = "TVIP";
        string memory baseURI = vm.envString("VIP_BASE_URI");
        address owner = vm.envAddress("VIP_OWNER");
        uint256 maxSupply = 500;
        address minter = vm.envAddress("VIP_MINTER");

        vm.startBroadcast();
        AITVERC721MintableBase vip = new AITVERC721MintableBase(
            owner,
            name,
            symbol,
            baseURI
        );
        vip.setMaxSupply(maxSupply);
        vip.grantRole(vip.MINTER_ROLE(), minter);
        vm.stopBroadcast();

        console.log("VIP NFT deployed at %s", address(vip));
        console.log("Owner: %s", owner);
        console.log("Minter: %s", minter);
        console.log("Max supply: %s", maxSupply);
        console.log("Name/Symbol: %s / %s", name, symbol);
        console.log("Base URI: %s", baseURI);
    }
}



