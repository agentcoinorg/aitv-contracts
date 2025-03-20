// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {LaunchPoolInfo} from "../../src/types/LaunchPoolInfo.sol";


contract AgentLaunchPoolDepositERC20Test is AgentFactoryTestUtils {
    MockedERC20 collateral;

    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();

        collateral = new MockedERC20();
    }

    function test_collateralIsCorrect() public {
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        LaunchPoolInfo memory launchPoolInfo = pool.getLaunchPoolInfo();

        assertEq(launchPoolInfo.collateral, address(collateral));
    }

    function test_canDepositERC20() public { 
        address user = makeAddr("user");
        collateral.mint(user, 1e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 1e18);
        pool.depositERC20(1e18);

        assertEq(pool.deposits(user), 1e18);
    }

    function test_multipleUsersCanDepositERC20() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        collateral.mint(user1, 1 * 1e18);
        collateral.mint(user2, 2 * 1e18);
        collateral.mint(user3, 3 * 1e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user1);
        collateral.approve(address(pool), 1e18);
        pool.depositERC20(1 * 1e18);
        
        vm.startPrank(user2);
        collateral.approve(address(pool), 2e18);
        pool.depositERC20(2 * 1e18);
        
        vm.startPrank(user3);
        collateral.approve(address(pool), 3e18);
        pool.depositERC20(3 * 1e18);

        assertEq(pool.deposits(user1), 1 * 1e18);
        assertEq(pool.deposits(user2), 2 * 1e18);
        assertEq(pool.deposits(user3), 3 * 1e18);
    }

    function test_forbidsDepositETH() public { 
        address user = makeAddr("user");
        collateral.mint(user, 1 * 1e18);
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.prank(user);
        vm.expectRevert(AgentLaunchPool.InvalidCollateral.selector);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user), 0);
    }

    function test_sameUserCanDepositMultipleTimes() public { 
        address user = makeAddr("user");
        collateral.mint(user, 10e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
      
        collateral.approve(address(pool), 3e18);

        pool.depositERC20(1e18);
        assertEq(pool.deposits(user), 1e18);
      
        pool.depositERC20(2e18);
        assertEq(pool.deposits(user), 3e18);
    }

    function test_forbidsDepositBySendingETH() public { 
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);

        vm.expectRevert(AgentLaunchPool.InvalidCollateral.selector);
        address(pool).call{value: 1 ether}("");

        assertEq(pool.deposits(user), 0);
    }

    function test_canDepositForBeneficiary() public { 
        address user = makeAddr("user");
        address beneficiary = makeAddr("beneficiary");

        collateral.mint(user, 1e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 1e18);
        pool.depositERC20For(beneficiary, 1e18);

        assertEq(pool.deposits(beneficiary), 1e18);
        assertEq(pool.deposits(user), 0);
    }

    function test_forbidsDepositAfterTimeWindow() public { 
        address user = makeAddr("user");
        collateral.mint(user, 1e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);

        vm.warp(block.timestamp + timeWindow);
        
        collateral.approve(address(pool), 1e18);
        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositERC20(1e18);

        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositERC20For(makeAddr("beneficiary"), 1e18);
    }

    function test_depositOverMaxAmountDoesNotExceedMaxAmount() public {
        address user = makeAddr("user");
        collateral.mint(user, 15e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 11e18);
      
        pool.depositERC20(1e18);
        assertEq(pool.deposits(user), 1e18);

        pool.depositERC20(11e18);
        assertEq(pool.deposits(user), 10e18);

        assertEq(collateral.balanceOf(user), 5e18);
    }

    function test_canLaunchWhenMaxAmountIsReachedBeforeTimeWindow() public {
        address user = makeAddr("user");
        collateral.mint(user, 15e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 11e18);
        pool.depositERC20(11e18);
        vm.stopPrank();
    
        pool.launch();
    }

    function forbidsDepositAfterLaunch() public { 
        address user = makeAddr("user");
        collateral.mint(user, 10e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(collateral));

        vm.startPrank(user);
        collateral.approve(address(pool), 2e18);
       
        pool.depositERC20(1e18);

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositERC20(1e18);
    }
}

