// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";

contract DeployAgentTokenImplScript is Script {
    function run() public {
        vm.startBroadcast();
        AgentToken token = new AgentToken();
        vm.stopBroadcast();

        console.log("AgentToken implementation deployed at %s", address(token));
    }
}
