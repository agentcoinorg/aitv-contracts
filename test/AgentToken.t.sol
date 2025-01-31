// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {AgentToken} from "../src/AgentToken.sol";

contract AgentTokenTest is Test {
    AgentToken private token;
    address private owner = makeAddr("owner");

    function setUp() public {
        token = AgentToken(_deployAgentToken(owner));
    }

    function test_ownerIsSetCorrectly() public view {
        assertEq(token.owner(), owner);
    }

    function test_ownerCanUpgrade() public {
        vm.startPrank(owner);

        token.upgradeToAndCall(address(new AgentTokenV2Mock()), "");

        assertEq(AgentTokenV2Mock(address(token)).test(), true);

        vm.stopPrank();
    }

    function test_ownerCannotUpgradeToNonContract() public {
        vm.startPrank(owner);

        vm.expectRevert();
        token.upgradeToAndCall(address(0), "");

        vm.expectRevert();
        token.upgradeToAndCall(makeAddr("nonContract"), "");

        vm.stopPrank();
    }

    function test_nonOwnerCannotUpgrade() public {
        address newImplementation = address(new AgentTokenV2Mock());

        vm.startPrank(makeAddr("nonOwner"));

        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        token.upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function test_cannotCallInitializerInImplementation() public {
        AgentToken newImplementation = new AgentToken();

        address[] memory recipients = new address[](1);
        recipients[0] = owner;

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 10_000_000 * 1e18;

        string memory name = "AgentToken";
        string memory symbol = "TOKEN";

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        newImplementation.initialize(name, symbol, owner, recipients, amounts);
    }

    function test_canRenounceOwnership() public {
        vm.startPrank(owner);

        token.renounceOwnership();

        address newImplementation = address(new AgentTokenV2Mock());

        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        token.upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function test_canTransferOwnership() public {
        vm.startPrank(owner);

        token.transferOwnership(makeAddr("newOwner"));

        address newImplementation = address(new AgentTokenV2Mock());

        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        token.upgradeToAndCall(newImplementation, "");

        vm.stopPrank();

        vm.startPrank(makeAddr("newOwner"));

        token.upgradeToAndCall(newImplementation, "");

        vm.stopPrank();
    }

    function test_canTransferTokens() public {
        vm.startPrank(owner);

        token.transfer(makeAddr("new-recipient"), 100);

        assertEq(token.balanceOf(makeAddr("new-recipient")), 100);

        vm.stopPrank();
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
}

contract  AgentTokenV2Mock is AgentToken {
    function test() public pure returns(bool) {
        return true;
    }
}