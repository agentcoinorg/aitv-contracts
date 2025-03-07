// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";
import {AgentLaunchPool} from "../src/AgentLaunchPool.sol";
import {
    IAgentLaunchPool,
    TokenInfo,
    LaunchPoolInfo,
    UniswapPoolInfo,
    AgentDistributionInfo
} from "../src/interfaces/IAgentLaunchPool.sol";
import {AgentFactory} from "../src/AgentFactory.sol";
import {AgentUniswapHook} from "../src/AgentUniswapHook.sol";
import {UniswapFeeInfo} from "../src/interfaces/IFeeSetter.sol";
import {AgentFactoryTestUtils} from "./helpers/AgentFactoryTestUtils.sol";


contract AgentFactoryTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_factory() public {
        _deployDefaultLaunchPool(factory);
    }
}

