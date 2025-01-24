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
