// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentUniswapHook} from "../src/AgentUniswapHook.sol";
import {AgentUniswapHookDeployer} from "../src/AgentUniswapHookDeployer.sol";

contract DeployAgentUniswapHookScript is Script, AgentUniswapHookDeployer {
    function run() public {
        address owner = vm.envAddress("HOOK_OWNER");
        address agentFactory = vm.envAddress("AGENT_FACTORY");
        address uniswapPoolManager = vm.envAddress("BASE_POOL_MANAGER");

        vm.startBroadcast();
        AgentUniswapHook impl = new AgentUniswapHook();
        vm.stopBroadcast();

        console.log("AgentUniswapHook implementation deployed at %s", address(impl));
        
        AgentUniswapHook hook = _deployAgentUniswapHook(owner, agentFactory, uniswapPoolManager, address(impl), true);

        console.log("AgentUniswapHook proxy deployed at %s", address(hook));

        require(owner == hook.owner(), "Owner mismatch");
        require(agentFactory == hook.controller(), "AgentFactory should be controller");
        require(uniswapPoolManager == address(hook.poolManager()), "UniswapPoolManager mismatch");
    }
}
