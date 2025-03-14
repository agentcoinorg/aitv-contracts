// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PoolKey} from '@uniswap/v4-core/src/types/PoolKey.sol';
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";
import {AgentToken} from "../../src/AgentToken.sol";

contract AgentLaunchPoolReclaimERC20Test is AgentFactoryTestUtils {
    MockedERC20 collateral;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();

        collateral = new MockedERC20();
    }

    function test_canReclaimDepositsIfLaunchFails() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0);
        assertEq(collateral.balanceOf(user), 100e18);
    }

    function test_canReclaimIfMultipleDeposits() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.2 * 1e18);
        pool.depositERC20(0.3 * 1e18);
        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0);
        assertEq(collateral.balanceOf(user), 100e18);
    }

    function test_canReclaimERC20DepositsForBeneficiary() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(makeAddr("anon")); 
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0);
        assertEq(collateral.balanceOf(user), 100e18);
    }

    function test_multipleUsersCanReclaimDeposits() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        collateral.mint(user1, 100e18);
        collateral.mint(user2, 100e18);
        collateral.mint(user3, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user1);
        collateral.approve(address(pool), 0.1 * 1e18);
        pool.depositERC20(0.1 * 1e18);
        assertEq(pool.deposits(user1), 0.1 * 1e18);
        assertEq(collateral.balanceOf(user1), 100e18 - 0.1 * 1e18);

        vm.startPrank(user2);
        collateral.approve(address(pool), 0.2 * 1e18);
        pool.depositERC20(0.2 * 1e18);
        assertEq(pool.deposits(user2), 0.2 * 1e18);
        assertEq(collateral.balanceOf(user2), 100e18 - 0.2 * 1e18);

        vm.startPrank(user3);
        collateral.approve(address(pool), 0.3 * 1e18);
        pool.depositERC20(0.3 * 1e18);
        assertEq(pool.deposits(user3), 0.3 * 1e18);
        assertEq(collateral.balanceOf(user3), 100e18 - 0.3 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        vm.startPrank(user1);
        pool.reclaimERC20DepositsFor(user1);
        assertEq(pool.deposits(user1), 0);
        assertEq(collateral.balanceOf(user1), 100e18);

        vm.startPrank(user2);
        pool.reclaimERC20DepositsFor(user2);
        assertEq(pool.deposits(user2), 0);
        assertEq(collateral.balanceOf(user2), 100e18);

        vm.startPrank(user3);
        pool.reclaimERC20DepositsFor(user3);
        assertEq(pool.deposits(user3), 0);
        assertEq(collateral.balanceOf(user3), 100e18);
    }

    function test_forbidsReentrantReclaiming() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimERC20DepositsFor(user);

        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0);
        assertEq(collateral.balanceOf(user), 100e18);
    }

    function test_forbidsReclaimingIfBeneficiaryAlreadyClaimed() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(makeAddr("anon1"));
        pool.reclaimERC20DepositsFor(user);

        vm.prank(makeAddr("anon2"));
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0);
        assertEq(collateral.balanceOf(user), 100e18);
    }

    function test_forbidsReclaimingBeforeTimeWindow() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);

        vm.warp(block.timestamp + timeWindow / 2);

        vm.expectRevert(AgentLaunchPool.TimeWindowNotPassed.selector);
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);
    }

    function test_forbidsReclaimingIfMinAmountReached() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 1 * 1e18);
        pool.depositERC20(1 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert(AgentLaunchPool.MinAmountReached.selector);
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 1e18);
    }

    function test_forbidsReclaimingIfBeneficiaryNeverDeposited() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        vm.stopPrank();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(user);
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimERC20DepositsFor(makeAddr("non-depositor"));

        vm.prank(makeAddr("non-depositor"));
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimERC20DepositsFor(makeAddr("non-depositor"));

        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(pool.deposits(makeAddr("non-depositor")), 0);
        assertEq(collateral.balanceOf(user), 100 * 1e18 - 0.5 * 1e18);
    }

    function test_forbidsReclaimingETHDeposits() public { 
        address user = makeAddr("user");
        collateral.mint(user, 100e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 0.5 * 1e18);
        pool.depositERC20(0.5 * 1e18);
        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert(AgentLaunchPool.InvalidCollateral.selector);
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0.5 * 1e18);
        assertEq(collateral.balanceOf(user), 100e18 - 0.5 * 1e18);
    }
}

