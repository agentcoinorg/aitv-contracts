// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentStaking} from "../src/AgentStaking.sol";

contract DeployAgentStaking is Script {
    function setUp() public {}

    function run() public {
        deploy();
    }

    function deploy() public  {
        address daoAddress = vm.envAddress("DAO_ADDRESS");
        address agentTokenAddress = vm.envAddress("AGENT_TOKEN_ADDRESS");

        vm.startBroadcast();
        
        AgentStaking implementation = new AgentStaking();

        new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentStaking.initialize, (daoAddress, agentTokenAddress))
        );

        vm.stopBroadcast();
    }
}
