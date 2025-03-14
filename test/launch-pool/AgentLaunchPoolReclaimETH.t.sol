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

contract AgentLaunchPoolReclaimETHTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canReclaimDepositsIfLaunchFails() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.5 ether}();
        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 100 ether);
    }

    function test_canReclaimIfMultipleDeposits() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.2 ether}();
        pool.depositETH{value: 0.3 ether}();
        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 100 ether);
    }

    function test_canreclaimETHDepositsForBeneficiary() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 0.5 ether}();
        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);

        vm.warp(block.timestamp + timeWindow);

        vm.prank(makeAddr("anon")); 
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 100 ether);
    }

    function test_multipleUsersCanReclaimDeposits() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user1);
        pool.depositETH{value: 0.1 ether}();
        assertEq(pool.deposits(user1), 0.1 ether);
        assertEq(user1.balance, 100 ether - 0.1 ether);

        vm.prank(user2);
        pool.depositETH{value: 0.2 ether}();
        assertEq(pool.deposits(user2), 0.2 ether);
        assertEq(user2.balance, 100 ether - 0.2 ether);

        vm.prank(user3);
        pool.depositETH{value: 0.3 ether}();
        assertEq(pool.deposits(user3), 0.3 ether);
        assertEq(user3.balance, 100 ether - 0.3 ether);

        vm.warp(block.timestamp + timeWindow);

        vm.prank(user1);
        pool.reclaimETHDepositsFor(payable(user1));
        assertEq(pool.deposits(user1), 0);
        assertEq(user1.balance, 100 ether);

        vm.prank(user2);
        pool.reclaimETHDepositsFor(payable(user2));
        assertEq(pool.deposits(user2), 0);
        assertEq(user2.balance, 100 ether);

        vm.prank(user3);
        pool.reclaimETHDepositsFor(payable(user3));
        assertEq(pool.deposits(user3), 0);
        assertEq(user3.balance, 100 ether);
    }

    function test_forbidsReentrantReclaiming() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.5 ether}();
        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);

        vm.warp(block.timestamp + timeWindow);

        pool.reclaimETHDepositsFor(payable(user));

        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 100 ether);
    }

    function test_forbidsReclaimingIfBeneficiaryAlreadyClaimed() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 0.5 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(makeAddr("anon1"));
        pool.reclaimETHDepositsFor(payable(user));

        vm.prank(makeAddr("anon2"));
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0);
        assertEq(user.balance, 100 ether);
    }

    function test_forbidsReclaimingBeforeTimeWindow() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.5 ether}();

        vm.warp(block.timestamp + timeWindow / 2);

        vm.expectRevert(AgentLaunchPool.TimeWindowNotPassed.selector);
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);
    }

    function test_forbidsReclaimingIfMinAmountReached() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert(AgentLaunchPool.MinAmountReached.selector);
        pool.reclaimETHDepositsFor(payable(user));

        assertEq(pool.deposits(user), 1 ether);
        assertEq(user.balance, 100 ether - 1 ether);
    }

    function test_forbidsReclaimingIfBeneficiaryNeverDeposited() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 0.5 ether}();

        vm.warp(block.timestamp + timeWindow);

        vm.prank(user);
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimETHDepositsFor(payable(makeAddr("non-depositor")));

        vm.prank(makeAddr("non-depositor"));
        vm.expectRevert(AgentLaunchPool.NotDeposited.selector);
        pool.reclaimETHDepositsFor(payable(makeAddr("non-depositor")));

        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(pool.deposits(makeAddr("non-depositor")), 0 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);
    }

    function test_forbidsReclaimingERC20Deposits() public { 
        address user = makeAddr("user");
        vm.deal(user, 100 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 0.5 ether}();
        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);

        vm.warp(block.timestamp + timeWindow);

        vm.expectRevert(AgentLaunchPool.InvalidCollateral.selector);
        pool.reclaimERC20DepositsFor(user);

        assertEq(pool.deposits(user), 0.5 ether);
        assertEq(user.balance, 100 ether - 0.5 ether);
    }
}

