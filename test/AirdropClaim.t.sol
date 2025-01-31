// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {AgentToken} from "../src/AgentToken.sol";
import {AirdropClaim} from "../src/AirdropClaim.sol";

contract AirdropClaimTest is Test {
    MockedERC20 public geckoV1;
    MockedERC20 public geckoV2;
    AirdropClaim public airdrop;

    address public user = makeAddr("user");
    address public owner = makeAddr("owner");
    address public recipient = makeAddr("recipient");
    address public otherUser = makeAddr("otherUser");

    function setUp() public {
        geckoV1 = new MockedERC20("GeckoV1", "GECKO");
        airdrop = new AirdropClaim(address(geckoV1));
        geckoV2 = new MockedERC20("GeckoV2", "GECKO");
        geckoV2.mint(address(this), 1_000_000 * 1e18);
        geckoV2.approve(address(airdrop), 1_000_000 * 1e18);
        airdrop.deposit(address(geckoV2), 1_000_000 * 1e18);
    }

    function test_forbidsDepositingMoreThanOnce() public {
        geckoV2.mint(address(this), 1_000_000 * 1e18);
        geckoV2.approve(address(airdrop), 1_000_000 * 1e18);

        vm.expectRevert(AirdropClaim.AlreadyDeposited.selector);
        airdrop.deposit(address(geckoV2), 1_000_000 * 1e18);
    }

    function test_canClaim() public {
        uint256 amount = 100 * 1e18;

        geckoV1.mint(user, amount);

        assertEq(geckoV2.balanceOf(user), 0);

        vm.prank(user);
        airdrop.claim(user);

        assertEq(geckoV2.balanceOf(user), 1_000_000 * 1e18);
    }

    function test_claimingMultipleTimesResultsInNoBenefit() public {
        uint256 amount1 = 100 * 1e18;
        uint256 amount2 = 50 * 1e18;

        geckoV1.mint(user, amount1);
        geckoV1.mint(otherUser, amount2);

        vm.prank(user);
        airdrop.claim(user);
        airdrop.claim(user);
    
        assertEq(geckoV2.balanceOf(user), 1_000_000 * 1e18 * amount1 / (amount1 + amount2));
    }

    function test_multipleUsersCanClaim() public {
        uint256 amount1 = 100 * 1e18;
        uint256 amount2 = 50 * 1e18;

        geckoV1.mint(user, amount1);
        geckoV1.mint(otherUser, amount2);

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(otherUser), 0);

        vm.prank(user);
        airdrop.claim(user);

        vm.prank(recipient);
        airdrop.claim(otherUser);

        assertEq(geckoV2.balanceOf(user), 1_000_000 * 1e18 * amount1 / (amount1 + amount2));
        assertEq(geckoV2.balanceOf(otherUser), 1_000_000 * 1e18 * amount2 / (amount1 + amount2));
    }

    function test_canClaimForRecipient() public {
        uint256 amount = 100 * 1e18;

        geckoV1.mint(recipient, amount);

        assertEq(geckoV2.balanceOf(recipient), 0);

        vm.prank(user);
        airdrop.claim(recipient);

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(recipient), 1_000_000 * 1e18);
    }

    function test_nonHolderClaimingDoesNotGetTokens() public {
        assertEq(geckoV2.balanceOf(otherUser), 0);

        vm.prank(otherUser);
        airdrop.claim(otherUser);

        assertEq(geckoV2.balanceOf(otherUser), 0);
    }

    function test_canClaimMany() public {
        uint256 amount1 = 100 * 1e18;
        uint256 amount2 = 50 * 1e18;

        geckoV1.mint(user, amount1);
        geckoV1.mint(recipient, amount2);

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(recipient), 0);

        address[] memory addresses = new address[](2);
        addresses[0] = user;
        addresses[1] = recipient;

        vm.prank(user);
        airdrop.multiClaim(addresses);

        assertEq(geckoV2.balanceOf(user), 1_000_000 * 1e18 * amount1 / (amount1 + amount2));
        assertEq(geckoV2.balanceOf(recipient), 1_000_000 * 1e18 * amount2 / (amount1 + amount2));
    }

    function test_nonHolderCanClaimManyForOthers() public {
        uint256 amount1 = 100 * 1e18;
        uint256 amount2 = 50 * 1e18;

        geckoV1.mint(user, amount1);
        geckoV1.mint(recipient, amount2);

        assertEq(geckoV2.balanceOf(user), 0);
        assertEq(geckoV2.balanceOf(recipient), 0);

        address[] memory addresses = new address[](2);
        addresses[0] = user;
        addresses[1] = recipient;

        vm.prank(otherUser);
        airdrop.multiClaim(addresses);

        assertEq(geckoV2.balanceOf(user), 1_000_000 * 1e18 * amount1 / (amount1 + amount2));
        assertEq(geckoV2.balanceOf(recipient), 1_000_000 * 1e18 * amount2 / (amount1 + amount2));
    }
}

contract MockedERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}