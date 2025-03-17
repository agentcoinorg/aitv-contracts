// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {AgentFactory} from "../src/AgentFactory.sol";

contract DeployAgentFactoryScript is Script {
    function run() public {
        address owner = vm.envAddress("AGENT_FACTORY_OWNER");
        address uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");
        address uniswapPositionManager = vm.envAddress("BASE_POSITION_MANAGER");

        vm.startBroadcast();
        AgentFactory impl = new AgentFactory();
        vm.stopBroadcast();

        console.log("AgentFactory implementation deployed at %s", address(impl));
        
        vm.startBroadcast();
        ERC1967Proxy factory = new ERC1967Proxy(
            address(impl), abi.encodeCall(AgentFactory.initialize, (owner, uniswapPoolManager, uniswapPositionManager))
        );
        vm.stopBroadcast();

        console.log("AgentFactory proxy deployed at %s", address(factory));

        AgentFactory agentFactory = AgentFactory(address(factory));

        require(owner == agentFactory.owner(), "Owner mismatch");
        require(uniswapPoolManager == address(agentFactory.poolManager()), "UniswapPoolManager mismatch");
        require(uniswapPositionManager == address(agentFactory.positionManager()), "UniswapPositionManager mismatch");
    }
}
