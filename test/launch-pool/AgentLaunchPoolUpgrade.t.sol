// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {AgentUniswapHook} from "../../src/AgentUniswapHook.sol";

contract AgentLaunchPoolUpgradeTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canUpgradeLaunchPool() public { 
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));
    
        AgentLaunchPool newImplementation = new AgentLaunchPool();
    
        vm.prank(owner);
        pool.upgradeToAndCall(address(newImplementation), "");
    }

    function test_canUpgradeUniswapHook() public { 
        _deployDefaultLaunchPool(address(0));
    
        AgentUniswapHook impl = new AgentUniswapHook();
    
        vm.prank(owner);
        hook.upgradeToAndCall(address(impl), "");
    }

    function test_canUpgradeUniswapHookWithPreviouslyUnusedHookFunction() public { 
        (AgentLaunchPool pool, PoolKey memory poolKey) = _deployDefaultLaunchPool(address(0));

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        vm.prank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();
    
        AgentUniswapHookDisableAddLiquidity impl = new AgentUniswapHookDisableAddLiquidity();
    
        vm.prank(owner);
        hook.upgradeToAndCall(address(impl), "");

        address provider = makeAddr("provider");
        vm.deal(provider, 10 ether);

        _swapETHForERC20ExactIn(provider, poolKey, 1 ether);
        
        _mintLiquidityPositionExpectRevert(provider, poolKey, 1 ether, 10e18, 200);
    }

    function test_onlyOwnerCanUpgradeLaunchPool() public { 
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));
    
        AgentLaunchPool newImplementation = new AgentLaunchPool();
    
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        pool.upgradeToAndCall(address(newImplementation), "");
    }

    function test_onlyOwnerCanUpgradeUniswapHook() public { 
        _deployDefaultLaunchPool(address(0));
    
        AgentUniswapHook newImplementation = new AgentUniswapHook();
    
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        hook.upgradeToAndCall(address(newImplementation), "");
    }

    function test_newLaunchPoolImplementationWorks() public { 
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));
    
        AgentLaunchPoolDisableLaunch impl1 = new AgentLaunchPoolDisableLaunch();
        AgentLaunchPool impl2 = new AgentLaunchPool();
    
        vm.prank(owner);
        pool.upgradeToAndCall(address(impl1), "");

        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        vm.prank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert("Launch disabled");
        pool.launch();

        vm.prank(owner);
        pool.upgradeToAndCall(address(impl2), "");

        pool.launch();
    }
}

contract AgentLaunchPoolDisableLaunch is AgentLaunchPool {
    function launch() external pure override {
        revert ("Launch disabled");
    }
}

contract AgentUniswapHookDisableSwap is AgentUniswapHook {
    function _beforeSwap(
        address,
        PoolKey calldata,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) internal pure override returns (bytes4, BeforeSwapDelta, uint24) {
        revert ("Swap disabled");
    }
}

contract AgentUniswapHookDisableAddLiquidity is AgentUniswapHook {
    function _beforeAddLiquidity(address, PoolKey calldata, IPoolManager.ModifyLiquidityParams calldata, bytes calldata)
        internal
        virtual
        override
        returns (bytes4) {
        revert ("Add liquditiy disabled");
    }
}
