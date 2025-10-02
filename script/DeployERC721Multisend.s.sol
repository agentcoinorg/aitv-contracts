// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ERC721Multisend} from "../src/ERC721Multisend.sol";

contract DeployERC721MultisendScript is Script {
    function run() public {
        vm.startBroadcast();
        ERC721Multisend multisend = new ERC721Multisend();
        vm.stopBroadcast();

        console.log("ERC721Multisend deployed at %s", address(multisend));
    }
}


