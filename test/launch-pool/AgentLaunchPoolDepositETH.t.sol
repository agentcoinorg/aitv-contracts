// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {MockedERC20} from "../helpers/MockedERC20.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";


contract AgentLaunchPoolDepositETHTest is AgentFactoryTestUtils {
    
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canDepositETH() public { 
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETH{value: 1 ether}();

        assertEq(pool.deposits(user), 1 ether);
    }

    function test_multipleUsersCanDepositETH() public { 
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        vm.deal(user1, 1 ether);
        vm.deal(user2, 2 ether);
        vm.deal(user3, 3 ether);


        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user1);
        pool.depositETH{value: 1 ether}();
        vm.prank(user2);
        pool.depositETH{value: 2 ether}();
        vm.prank(user3);
        pool.depositETH{value: 3 ether}();

        assertEq(pool.deposits(user1), 1 ether);
        assertEq(pool.deposits(user2), 2 ether);
        assertEq(pool.deposits(user3), 3 ether);
    }

    function test_forbidsDepositERC20() public { 
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        MockedERC20 collateral = new MockedERC20();
        collateral.mint(user, 10 * 1e18);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        vm.expectRevert(AgentLaunchPool.InvalidCollateral.selector);
        pool.depositERC20(1 * 1e18);

        assertEq(pool.deposits(user), 0);
    }

    function test_sameUserCanDepositMultipleTimes() public { 
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
      
        pool.depositETH{value: 1 ether}();
        assertEq(pool.deposits(user), 1 ether);
      
        pool.depositETH{value: 2 ether}();
        assertEq(pool.deposits(user), 3 ether);
    }

    function test_canDepositBySendingETH() public { 
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);

        address(pool).call{value: 1 ether}("");
        assertEq(pool.deposits(user), 1 ether);

        address(pool).call{value: 2 ether}("");
        assertEq(pool.deposits(user), 3 ether);
    }

    function test_canDepositForBeneficiary() public { 
        address user = makeAddr("user");
        address beneficiary = makeAddr("beneficiary");

        vm.deal(user, 1 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.prank(user);
        pool.depositETHFor{value: 1 ether}(beneficiary);

        assertEq(pool.deposits(beneficiary), 1 ether);
        assertEq(pool.deposits(user), 0);
    }

    function test_forbidsDepositAfterTimeWindow() public { 
        address user = makeAddr("user");
        vm.deal(user, 1 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);

        vm.warp(block.timestamp + timeWindow);
        
        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETH{value: 1 ether}();

        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETHFor{value: 1 ether}(makeAddr("beneficiary"));
    }

    function test_forbidsDepositOverMaxAmount() public {
        address user = makeAddr("user");
        vm.deal(user, 20 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
      
        pool.depositETH{value: 1 ether}();
        assertEq(pool.deposits(user), 1 ether);

        pool.depositETH{value: 11 ether}();
        assertEq(pool.deposits(user), 10 ether);

        assertEq(user.balance, 10 ether);
    }

    function forbidsDepositAfterLaunch() public { 
        address user = makeAddr("user");
        vm.deal(user, 10 ether);

        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));

        vm.startPrank(user);
        pool.depositETH{value: 1 ether}();

        vm.warp(block.timestamp + timeWindow);

        pool.launch();

        vm.expectRevert(AgentLaunchPool.DepositsClosed.selector);
        pool.depositETH{value: 1 ether}();
    }
}

