// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentTokenV2} from "../src/AgentTokenV2.sol";
import {AgentStaking} from "../src/AgentStaking.sol";

contract AgentStakingTest is Test {
    IERC20 public key;
    AgentStaking public staking;

    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");
    address public owner = makeAddr("owner");

    function setUp() public {
        key = IERC20(_deployAgentKey(owner));
        staking = AgentStaking(_deployAgentStaking(owner, address(key)));
    }

    function test_canStake() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(key.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount);
    }

    function test_canStakeMultipleTimesWithoutUnstaking() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount * 2);

        assertEq(key.balanceOf(user), amount * 2);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(key.balanceOf(user), amount);
        assertEq(staking.getStakedAmount(user), amount);

        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount * 2);
    }

    function test_canUnstake() public {
        uint256 amount = 100 * 1e18;
      
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
        uint256 amount = 100 * 1e18;

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

    function test_canClaimToAnotherAccount() public {
        uint256 amount = 100 * 1e18;

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
    
        staking.claim(1, recipient);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(key.balanceOf(user), 0);
        assertEq(key.balanceOf(recipient), amount);
    }

    function test_forbidsClaimingBeforeUnstakeLockPeriod() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount);

        assertEq(key.balanceOf(user), amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 hours);

        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(key.balanceOf(user), 0);
    }

    function test_forbidsStakingZero() public {
        vm.startPrank(user);

        vm.expectRevert(AgentStaking.EmptyAmount.selector);
        staking.stake(0);
    }

    function test_forbidsUnstakingZero() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        vm.expectRevert(AgentStaking.EmptyAmount.selector);
        staking.unstake(0);
    }

    function test_forbidsUnstakingMoreThanStaked() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        vm.expectRevert(AgentStaking.InsufficientStakedBalance.selector);
        staking.unstake(amount + 1);
    }

    function test_forbidsClaimingIfNoLockedWithdrawals() public {
        vm.startPrank(user);

        vm.expectRevert(AgentStaking.NoLockedWithdrawalsFound.selector);
        staking.claim(1, user);
    }

    function test_cannotClaimMoreThanStaked() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        key.transfer(user, amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);

        staking.claim(2, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(key.balanceOf(user), amount);
    }

    function test_canUnstakeAndClaimMultipleOneByOne() public {
        uint256 amount = 100 * 1e18;

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
        uint256 amount = 100 * 1e18;

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

        assertEq(key.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount / 4);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        staking.claim(3, user);

        assertEq(key.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }

    function test_canClaimAllAtOnce() public {
        uint256 amount = 100 * 1e18;

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
        vm.warp(block.timestamp + 2 hours);
        staking.unstake(amount / 4);

        assertEq(key.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), 0);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        staking.claim(4, user);

        assertEq(key.balanceOf(user), amount);
        assertEq(staking.getStakedAmount(user), 0);
    }

    function test_canReadMultipleWithdrawals() public {
        uint256 amount = 100 * 1e18;

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

    function test_canReadWithdrawalsAfterOneUnstake() public {
        uint256 amount = 100 * 1e18;
      
        vm.prank(owner);
        key.transfer(user, amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, user);

        key.approve(address(staking), amount);
        staking.stake(amount / 2);

        staking.unstake(amount / 2);

        AgentStaking.LockedWithdrawal[] memory withdrawals = staking.getWithdrawals(user, 0, 1);

        assertEq(withdrawals.length, 1);
        assertEq(withdrawals[0].amount, amount / 2);
    }


    function test_canStakeUnstakeStake() public {
        uint256 amount = 100 * 1e18;
      
        vm.prank(owner);
        key.transfer(user, amount);

        vm.startPrank(user);
        key.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(key.balanceOf(user), 0);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, user);

        key.approve(address(staking), amount);
        staking.stake(amount / 4);

        assertEq(key.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
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

        AgentTokenV2 implementation = new AgentTokenV2();

        address[] memory recipients = new address[](1);
        recipients[0] = _owner;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000_000 * 1e18;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentTokenV2.initialize, (name, symbol, _owner, recipients, amounts))
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
