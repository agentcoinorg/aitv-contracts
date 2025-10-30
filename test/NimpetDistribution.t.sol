// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {TokenDistributorTest} from "./TokenDistributor.t.sol";
import {DistributionBuilder} from "../src/DistributionBuilder.sol";
import {TokenDistributor, Action, ActionType, Swap} from "../src/TokenDistributor.sol";
import {PancakeProposal, PancakeConfig} from "../src/types/PancakeConfig.sol";

contract NimpetDistributionTest is TokenDistributorTest {
    function test_buildAndInspectNimpetDistribution() public {
        // Use hardcoded BSC addresses from AddNimpetDistribution.sol
        address USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
        address USDT = 0x55d398326f99059fF775485246999027B3197955;
        address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        address AITV = makeAddr("AITV_BSC");
        address NIMPET = 0x87aa6aEb62ff128aAA96E275d7B24cd12a72ABa1; // PUBLIC/NIMPET

        vm.startPrank(owner);

        // Configure Pancake routes as in AddNimpetDistribution.sol
        uint256 cfg1 = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: USDT, tokenB: USDC, fee: 100 })
        );
        distributor.setPancakeConfig(cfg1);

        uint256 cfg2 = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: USDT, tokenB: NIMPET, fee: 100 })
        );
        distributor.setPancakeConfig(cfg2);

        uint256 cfg3 = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: USDC, tokenB: WBNB, fee: 100 })
        );
        distributor.setPancakeConfig(cfg3);

        uint256 cfg4 = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: WBNB, tokenB: AITV, fee: 100 })
        );
        distributor.setPancakeConfig(cfg4);

        // Verify Pancake configs are stored
        PancakeConfig memory c1 = distributor.getPancakeConfig(USDT, USDC);
        assertTrue(c1.exists);
        assertEq(c1.fee, 100);

        PancakeConfig memory c2 = distributor.getPancakeConfig(USDT, NIMPET);
        assertTrue(c2.exists);
        assertEq(c2.fee, 100);

        PancakeConfig memory c3 = distributor.getPancakeConfig(USDC, WBNB);
        assertTrue(c3.exists);
        assertEq(c3.fee, 100);

        PancakeConfig memory c4 = distributor.getPancakeConfig(WBNB, AITV);
        assertTrue(c4.exists);
        assertEq(c4.fee, 100);

        // Sub-distribution: USDT -> NIMPET (100%)
        Action[] memory nimpetChild = new DistributionBuilder()
            .buy(10_000, NIMPET, address(0))
            .build();
        uint256 nimpetChildId = distributor.addDistribution(nimpetChild);

        // Sub-distribution: WBNB -> AITV (100%)
        Action[] memory aitvChild = new DistributionBuilder()
            .buy(10_000, AITV, address(0))
            .build();
        uint256 aitvChildId = distributor.addDistribution(aitvChild);

        // Parent distribution: 20% to AITV via WBNB, 80% to NIMPET via USDT
        Action[] memory parent = new DistributionBuilder()
            .buy(2_000, WBNB, aitvChildId)
            .buy(8_000, USDT, nimpetChildId)
            .build();
        uint256 distributionId = distributor.addDistribution(parent);
        distributor.setDistributionId("nimpet", distributionId);

        vm.stopPrank();

        // Validate distribution id mapping
        assertEq(distributor.getDistributionIdByName("nimpet"), distributionId);

        // Validate parent structure
        Action[] memory storedParent = distributor.getDistributionByName("nimpet");
        assertEq(storedParent.length, 2);

        assertEq(uint8(storedParent[0].actionType), uint8(ActionType.Buy));
        assertEq(storedParent[0].basisPoints, 2000);
        assertEq(storedParent[0].token, WBNB);
        assertEq(storedParent[0].distributionId, aitvChildId);

        assertEq(uint8(storedParent[1].actionType), uint8(ActionType.Buy));
        assertEq(storedParent[1].basisPoints, 8000);
        assertEq(storedParent[1].token, USDT);
        assertEq(storedParent[1].distributionId, nimpetChildId);

        // Validate child distributions
        Action[] memory aitvActions = distributor.getDistributionById(aitvChildId);
        assertEq(aitvActions.length, 1);
        assertEq(uint8(aitvActions[0].actionType), uint8(ActionType.Buy));
        assertEq(aitvActions[0].basisPoints, 10_000);
        assertEq(aitvActions[0].token, AITV);

        Action[] memory nimpetActions = distributor.getDistributionById(nimpetChildId);
        assertEq(nimpetActions.length, 1);
        assertEq(uint8(nimpetActions[0].actionType), uint8(ActionType.Buy));
        assertEq(nimpetActions[0].basisPoints, 10_000);
        assertEq(nimpetActions[0].token, NIMPET);

        // Validate expected swap sequence when paying in USDT
        // Expected swaps:
        // 1) USDT -> WBNB (for the 20% path)
        // 2) WBNB -> AITV (child of 20% path)
        // 3) USDT -> USDT (parent buy recorded even if same token)
        // 4) USDT -> NIMPET (child of 80% path)
        Swap[] memory swaps = distributor.getSwapsByDistributionName("nimpet", USDT, 4);
        assertEq(swaps.length, 4);
        assertEq(swaps[0].tokenIn, USDT);
        assertEq(swaps[0].tokenOut, WBNB);
        assertEq(swaps[1].tokenIn, WBNB);
        assertEq(swaps[1].tokenOut, AITV);
        assertEq(swaps[2].tokenIn, USDT);
        assertEq(swaps[2].tokenOut, USDT);
        assertEq(swaps[3].tokenIn, USDT);
        assertEq(swaps[3].tokenOut, NIMPET);
    }
}


