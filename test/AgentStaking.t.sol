// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AgentStaking} from "../src/AgentStaking.sol";

contract AgentStakingTest is Test {
    IERC20 public token;
    AgentStaking public staking;

    address public user = makeAddr("user");
    address public recipient = makeAddr("recipient");
    address public owner = makeAddr("owner");

    function setUp() public {
        token = IERC20(_deployAgentToken(owner));
        staking = AgentStaking(_deployAgentStaking(owner, address(token)));
    }

    function test_canStake() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(token.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount);
    }

    function test_canStakeMultipleTimesWithoutUnstaking() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount * 2);

        assertEq(token.balanceOf(user), amount * 2);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);
    
        assertEq(token.balanceOf(user), amount);
        assertEq(staking.getStakedAmount(user), amount);

        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount * 2);
    }

    function test_canUnstake() public {
        uint256 amount = 100 * 1e18;
      
        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function test_canClaimAfterUnstakeLockPeriod() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 days);

        assertEq(token.balanceOf(user), 0);
    
        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function test_canClaimToAnotherAccount() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 days);

        assertEq(token.balanceOf(user), 0);
    
        staking.claim(1, recipient);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), 0);
        assertEq(token.balanceOf(recipient), amount);
    }

    function test_forbidsClaimingBeforeUnstakeLockPeriod() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);

        vm.warp(block.timestamp + 1 hours);

        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), 0);
    }

    function test_forbidsStakingZero() public {
        vm.startPrank(user);

        vm.expectRevert(AgentStaking.EmptyAmount.selector);
        staking.stake(0);
    }

    function test_forbidsUnstakingZero() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        vm.expectRevert(AgentStaking.EmptyAmount.selector);
        staking.unstake(0);
    }

    function test_forbidsUnstakingMoreThanStaked() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
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
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);

        staking.claim(2, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function test_canUnstakeAndClaimMultipleOneByOne() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        _unstakeWarpAndClaim(user, amount / 4);
        _unstakeWarpAndClaim(user, amount / 4);
        _unstakeWarpAndClaim(user, amount / 4);

        assertEq(token.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }
    
    function test_canClaimMultipleAtOnce() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        // Unstake a few times in different time intervals
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);

        assertEq(token.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), amount / 4);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        staking.claim(3, user);

        assertEq(token.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }

    function test_canClaimAllAtOnce() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        // Unstake a few times in different time intervals
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 1 hours);
        staking.unstake(amount / 4);
        vm.warp(block.timestamp + 2 hours);
        staking.unstake(amount / 4);

        assertEq(token.balanceOf(user), 0);
        assertEq(staking.getStakedAmount(user), 0);

        vm.warp(block.timestamp + 1 days);

        vm.startPrank(user);
        staking.claim(4, user);

        assertEq(token.balanceOf(user), amount);
        assertEq(staking.getStakedAmount(user), 0);
    }

    function test_canReadMultipleWithdrawals() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        assertEq(token.balanceOf(user), amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

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
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, user);

        token.approve(address(staking), amount);
        staking.stake(amount / 2);

        staking.unstake(amount / 2);

        AgentStaking.LockedWithdrawal[] memory withdrawals = staking.getWithdrawals(user, 0, 1);

        assertEq(withdrawals.length, 1);
        assertEq(withdrawals[0].amount, amount / 2);
    }


    function test_canStakeUnstakeStake() public {
        uint256 amount = 100 * 1e18;
      
        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(token.balanceOf(user), 0);

        staking.unstake(amount);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, user);

        token.approve(address(staking), amount);
        staking.stake(amount / 4);

        assertEq(token.balanceOf(user), 3 * amount / 4);
        assertEq(staking.getStakedAmount(user), amount / 4);
    }
    
    function test_ownerCanUpgrade() public {
        address newImplementation = address(new AgentStakingV2Mock());

        vm.startPrank(owner);
        staking.upgradeToAndCall(newImplementation, "");

        assertEq(AgentStakingV2Mock(address(staking)).test(), true);
    }

    function test_forbidsNonOwnerFromUpgrading() public {
        address newImplementation = address(new AgentStakingV2Mock());

        vm.startPrank(user);
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        staking.upgradeToAndCall(newImplementation, "");
    }

    function test_upgradeUnlockTime() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        address newImplementation = address(new AgentStakingUnlock());

        vm.startPrank(owner);
        staking.upgradeToAndCall(newImplementation, "");

        vm.startPrank(user);
        staking.unstake(amount);

        vm.warp(block.timestamp + 1 days);
        
        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), 0);

        vm.warp(block.timestamp + 1 days);
        
        staking.claim(1, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(user), amount);
    }

    function test_canUpgradeDisableStaking() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        address newImplementation = address(new AgentStakingDisabled());

        vm.startPrank(owner);
        staking.upgradeToAndCall(newImplementation, "");

        vm.startPrank(user);
        vm.expectRevert("Staking is disabled");
        staking.stake(amount);
    }

    function test_canUpgradeDisableUnstaking() public {
        uint256 amount = 100 * 1e18;

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        address newImplementation = address(new AgentUnstaking());

        vm.startPrank(owner);
        staking.upgradeToAndCall(newImplementation, "");

        vm.startPrank(user);
        vm.expectRevert("Unstaking is disabled");
        staking.unstake(amount);
    }

    function test_canUpgradeAndAccessStorage() public {
        uint256 amount = 100 * 1e18;
        address newStaking = makeAddr("newStaking");

        vm.prank(owner);
        token.transfer(user, amount);

        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);

        assertEq(staking.getStakedAmount(user), amount);
        assertEq(token.balanceOf(newStaking), 0);

        address newImplementation = address(new AgentStakingAccessStorage());

        vm.startPrank(owner);
        staking.upgradeToAndCall(newImplementation, "");

        assertEq(staking.getStakedAmount(user), amount);
        assertEq(token.balanceOf(newStaking), 0);

        AgentStakingAccessStorage(address(staking)).migrate(newStaking, user);

        assertEq(staking.getStakedAmount(user), 0);
        assertEq(token.balanceOf(newStaking), amount);
    }

    function _unstakeWarpAndClaim(address staker, uint256 amount) internal {
        vm.startPrank(staker);

        uint256 startBalance = token.balanceOf(staker);
        staking.unstake(amount);
        assertEq(token.balanceOf(staker), startBalance);
        vm.warp(block.timestamp + 1 days);
        staking.claim(1, staker);
        assertEq(token.balanceOf(staker), startBalance + amount);
    }

    function _deployAgentToken(address _owner) internal returns(address) {
        string memory name = "AgentToken";
        string memory symbol = "TOKEN";

        AgentToken implementation = new AgentToken();

        address[] memory recipients = new address[](1);
        recipients[0] = _owner;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000_000 * 1e18;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentToken.initialize, (name, symbol, _owner, recipients, amounts))
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

contract AgentStakingV2Mock is AgentStaking {
    function test() public pure returns (bool) {
        return true;
    }
}

contract AgentStakingUnlock is AgentStaking {
    function unlock_time() public view override returns (uint256) {
        return 2 days;
    }
}

contract AgentStakingDisabled is AgentStaking {
    function stake(uint256 amount) public override {
        revert("Staking is disabled");
    }
}

contract AgentUnstaking is AgentStaking {
    function unstake(uint256 amount) public override {
        revert("Unstaking is disabled");
    }
}

contract AgentStakingAccessStorage is AgentStaking {
    using SafeERC20 for IERC20;
    
    function migrate(address newStakingAddress, address user) public {
        uint256 amount = stakes[user];

        if (amount == 0) {
            revert ("No stakes to migrate");
        }

        stakes[user] = 0;
        agentToken.transfer(newStakingAddress, amount);
    }
}