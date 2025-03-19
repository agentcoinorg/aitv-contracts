// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {AgentLaunchPoolView} from "../src/AgentLaunchPoolView.sol";

contract DeployAgentLaunchPoolViewScript is Script {
    function run() public {
        vm.startBroadcast();
        AgentLaunchPoolView agentLaunchPoolView = new AgentLaunchPoolView();
        vm.stopBroadcast();

        console.log("Deployed AgentLaunchPoolView at %s", address(agentLaunchPoolView));
    }
}
