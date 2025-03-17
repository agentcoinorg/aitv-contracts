// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";

contract DeployAgentLaunchPoolImplScript is Script {
    function run() public {
        vm.startBroadcast();
        AgentLaunchPool pool = new AgentLaunchPool();
        vm.stopBroadcast();

        console.log("AgentLaunchPool implementation deployed at %s", address(pool));
    }
}
