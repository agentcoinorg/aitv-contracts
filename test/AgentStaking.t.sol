// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentKeyV2} from "../src/AgentKeyV2.sol";
import {AgentStaking} from "../src/AgentStaking.sol";

contract AgentStakingTest is Test {
    IERC20 public key;
    AgentStaking public staking;

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");

    function setUp() public {
        key = IERC20(_deployAgentKey(owner));
        staking = AgentStaking(_deployAgentStaking(owner, address(key)));
    }

    function test_canStake() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(key.balanceOf(user), 0);
    }

    function test_canUnstake() public {
        uint256 amount = 100;
      
        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(key.balanceOf(user), 0);
    }

    function test_canClaimAfterUnstakeLockPeriod() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 days);

        assertEq(key.balanceOf(user), 0);
    
        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(key.balanceOf(user), amount);
    }

    function test_forbidsClaimingBeforeUnstakeLockPeriod() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 hours);

        vm.expectRevert(AgentStaking.LockPeriodNotOver.selector);
        staking.claim(1, user);
    }

    function test_canUnstakeAndClaimMultipleOneByOne() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        _unstakeWarpAndClaim(user, amount / 4);
        _unstakeWarpAndClaim(user, amount / 4);
        _unstakeWarpAndClaim(user, amount / 4);

        assertEq(key.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }
    
    function test_canClaimMultipleAtOnce() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        // Unstake a few times in different time intervals
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 days);

        assertEq(key.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount / 4);

        vm.startPrank(user);
        staking.claim(3, user);

        assertEq(key.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }

    function test_canReadMultipleWithdrawals() public {
        uint256 amount = 100;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        // Unstake a few times in different time intervals
        staking.unstake(amount / 10);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 10);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 5);
       
        AgentStaking.LockedWithdrawal[] memory withdrawals1 = staking.getWithdrawals(user, 0, 3);

        assertEq(withdrawals1.length, 3);
        assertEq(withdrawals1[0].amount, amount / 10);
        assertEq(withdrawals1[1].amount, amount / 10);
        assertEq(withdrawals1[2].amount, amount / 5);

        AgentStaking.LockedWithdrawal[] memory withdrawals2 = staking.getWithdrawals(user, 0, 4);

        assertEq(withdrawals2.length, 3);
        assertEq(withdrawals2[0].amount, amount / 10);
        assertEq(withdrawals2[1].amount, amount / 10);
        assertEq(withdrawals2[2].amount, amount / 5);

        AgentStaking.LockedWithdrawal[] memory withdrawals3 = staking.getWithdrawals(user, 0, 2);

        assertEq(withdrawals3.length, 2);
        assertEq(withdrawals3[0].amount, amount / 10);
        assertEq(withdrawals3[1].amount, amount / 10);

        AgentStaking.LockedWithdrawal[] memory withdrawals4 = staking.getWithdrawals(user, 1, 2);

        assertEq(withdrawals4.length, 2);
        assertEq(withdrawals4[0].amount, amount / 10);
        assertEq(withdrawals4[1].amount, amount / 5);
    }

    function _unstakeWarpAndClaim(address staker, uint256 amount) internal {
        vm.startPrank(staker);

        uint256 startBalance = key.balanceOf(staker);
        staking.unstake(amount);
        assertEq(key.balanceOf(staker), startBalance);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, staker);
        assertEq(key.balanceOf(staker), startBalance + amount);
    }

    function _deployAgentKey(address _owner) internal returns(address) {
        string memory name = "AgentKey";
        string memory symbol = "KEY";

        AgentKeyV2 implementation = new AgentKeyV2();

        address[] memory recipients = new address[](1);
        recipients[0] = _owner;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000_000;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentKeyV2.initialize, (name, symbol, _owner, recipients, amounts))
        );

        return address(proxy);
    }

    function _deployAgentStaking(address _owner, address agentToken) internal returns(address) {
        AgentStaking implementation = new AgentStaking();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentStaking.initialize, (_owner, agentToken))
        );

        return address(proxy);
    }
}
