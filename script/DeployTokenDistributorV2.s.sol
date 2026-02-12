// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {TokenDistributorV2} from "../src/TokenDistributorV2.sol";

contract DeployTokenDistributorV2Script is Script {
    function run() public {
        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_V2_OWNER");
        bool allowlistEnabled = vm.envOr("TOKEN_DISTRIBUTOR_V2_ALLOWLIST_ENABLED", false);

        vm.startBroadcast();
        TokenDistributorV2 distributor = new TokenDistributorV2(owner);
        distributor.setAllowlistEnabled(allowlistEnabled);
        vm.stopBroadcast();

        console.log("TokenDistributorV2 deployed at %s", address(distributor));
        console.log("TokenDistributorV2 owner: %s", owner);
        console.log("TokenDistributorV2 allowlist enabled: %s", allowlistEnabled);

        require(owner == distributor.owner(), "Owner mismatch");
        require(allowlistEnabled == distributor.allowlistEnabled(), "Allowlist state mismatch");
    }
}
