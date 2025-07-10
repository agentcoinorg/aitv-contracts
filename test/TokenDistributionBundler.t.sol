// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {MockedERC20} from "./helpers/MockedERC20.sol";
import {TokenDistributor, Action, ActionType} from "../src/TokenDistributor.sol";
import {TokenDistributionBundler} from "../src/TokenDistributionBundler.sol";
import {ITokenDistributor} from "../src/interfaces/ITokenDistributor.sol";
import {DistributionBuilder} from "../src/DistributionBuilder.sol";

contract TokenDistributionBundlerTest is Test {
    TokenDistributor distributor;
    TokenDistributionBundler bundler;
    MockedERC20 token;

    address user = address(0xBEEF);
    address recipient = address(0xCAFE);

    function setUp() public {
        distributor = new TokenDistributor();
        token = new MockedERC20();

        distributor.initialize(
            address(this),
            IPositionManager(address(0)),
            IUniversalRouter(address(0)),
            IPermit2(address(0)),
            address(0) // weth
        );

        bundler = new TokenDistributionBundler(address(distributor));
    }

    function test_addAndExecuteETHDistribution() public {
        Action[] memory actions = new DistributionBuilder().send(10000, recipient).build();
        uint256 distId = distributor.addDistribution(actions);
        distributor.setDistributionId("ethDist", distId);

        vm.deal(user, 1 ether);
        vm.prank(user);
        bundler.addETHDistribution{value: 0.5 ether}("ethDist", user, address(0), _buildMockMinAmountsOut(1), block.timestamp);

        vm.prank(user);
        bundler.executeETHDistributions(1);

        assertEq(recipient.balance, 0.5 ether);
    }

    function test_addAndExecuteERC20Distribution() public {
        Action[] memory actions = new DistributionBuilder().send(10000, recipient).build();
        uint256 distId = distributor.addDistribution(actions);
        distributor.setDistributionId("erc20Dist", distId);

        token.mint(user, 1e18);

        vm.startPrank(user);
        token.approve(address(bundler), 0.5 ether);
        bundler.addERC20Distribution("erc20Dist", user, 0.5 ether, address(token), address(0), _buildMockMinAmountsOut(1), block.timestamp);
        bundler.executeERC20Distributions(1);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 0.5 ether);
    }

    function test_skipsExpiredETHDistribution() public {
        vm.deal(user, 1 ether);
        Action[] memory actions = new DistributionBuilder().send(10000, recipient).build();
        uint256 distId = distributor.addDistribution(actions);
        distributor.setDistributionId("expired", distId);

        vm.prank(user);
        bundler.addETHDistribution{value: 0.2 ether}("expired", user, address(0), _buildMockMinAmountsOut(1), block.timestamp - 1);

        vm.prank(user);
        bundler.executeETHDistributions(1);

        assertEq(recipient.balance, 0);
        assertEq(bundler.getETHDistributionCount(), 0); // should be removed
    }

    function test_skipsExpiredERC20Distribution() public {
        Action[] memory actions = new DistributionBuilder().send(10000, recipient).build();
        uint256 distId = distributor.addDistribution(actions);
        distributor.setDistributionId("expired", distId);

        token.mint(user, 1e18);
        vm.startPrank(user);
        token.approve(address(bundler), 0.2 ether);
        bundler.addERC20Distribution("expired", user, 0.2 ether, address(token), address(0), _buildMockMinAmountsOut(1), block.timestamp - 1);
        bundler.executeERC20Distributions(1);
        vm.stopPrank();

        assertEq(token.balanceOf(recipient), 0);
        assertEq(bundler.getERC20DistributionCount(), 0);
    }

    function _buildMockMinAmountsOut(uint256 count) internal pure returns (uint256[] memory) {
        uint256[] memory out = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            out[i] = 1;
        }
        return out;
    }
}
