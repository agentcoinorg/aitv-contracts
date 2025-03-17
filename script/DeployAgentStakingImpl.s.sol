// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AgentStaking} from "../src/AgentStaking.sol";

contract DeployAgentStakingImplScript is Script {
    function run() public {
        vm.startBroadcast();
        AgentStaking staking = new AgentStaking();
        vm.stopBroadcast();

        console.log("AgentStaking implementation deployed at %s", address(staking));
    }
}
