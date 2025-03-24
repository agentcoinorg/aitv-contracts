// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {AgentFactoryTestUtils} from "../helpers/AgentFactoryTestUtils.sol";
import {AgentLaunchPool} from "../../src/AgentLaunchPool.sol";

contract AgentLaunchPoolOwnershipTest is AgentFactoryTestUtils {
    function setUp() public {
        vm.createSelectFork(vm.envString("BASE_RPC_URL"));

        _deployDefaultContracts();
    }

    function test_canTransferOwnership() public {
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));
        
        assertEq(pool.owner(), owner);

        vm.prank(owner);
        pool.transferOwnership(makeAddr("newOwner"));

        assertEq(pool.owner(), owner);
       
        vm.prank(makeAddr("newOwner"));
        pool.acceptOwnership();

        assertEq(pool.owner(), makeAddr("newOwner"));
    }

    function test_forbidsNonOwnerFromTransferringOwnership() public {
        (AgentLaunchPool pool,) = _deployDefaultLaunchPool(address(0));
       
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        pool.transferOwnership(makeAddr("newOwner"));

        vm.prank(makeAddr("anyone"));
        vm.expectPartialRevert(OwnableUpgradeable.OwnableUnauthorizedAccount.selector);
        pool.transferOwnership(makeAddr("newOwner"));

        assertEq(pool.owner(), owner);
    }
}
