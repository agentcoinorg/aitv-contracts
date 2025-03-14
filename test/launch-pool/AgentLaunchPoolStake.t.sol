// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';

import {AgentToken} from "../../src/AgentToken.sol";
import {AgentStaking} from "../../src/AgentStaking.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";

contract AgentLaunchPoolStakeTest is AgentFactoryTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canStakeAfterLaunch() public {
        address depositor = makeAddr("depositor");
        vm.deal(depositor, 1 ether);

        (AgentLaunchPool pool, PoolKey memory poolKey)= _deployDefaultLaunchPool(address(0));

        vm.prank(depositor);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        pool.claim(depositor);

        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        address token = pool.agentToken();

        _swapETHForERC20(user, poolKey, 1 ether);

        AgentStaking staking = AgentStaking(pool.agentStaking());

        uint256 startingUserBalance = IERC20(pool.agentToken()).balanceOf(user);
        uint256 userAmount = startingUserBalance / 3;

        vm.startPrank(user);
        IERC20(token).approve(address(staking), userAmount);
        staking.stake(userAmount);
        vm.stopPrank();

        uint256 startingDepositorBalance = IERC20(pool.agentToken()).balanceOf(depositor);
        uint256 depositorAmount = startingDepositorBalance / 3;

        vm.startPrank(depositor);
        IERC20(token).approve(address(staking), depositorAmount);
        staking.stake(depositorAmount);
        vm.stopPrank();
    
        assertEq(IERC20(token).balanceOf(user), startingUserBalance - userAmount);
        assertEq(staking.getStakedAmount(user), userAmount);

        assertEq(IERC20(token).balanceOf(depositor), startingDepositorBalance - depositorAmount);
        assertEq(staking.getStakedAmount(depositor), depositorAmount);
    }
}
