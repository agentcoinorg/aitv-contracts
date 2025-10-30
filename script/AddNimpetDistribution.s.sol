// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {PancakeProposal} from "../src/types/PancakeConfig.sol";
import {DistributionBuilder} from "../src/DistributionBuilder.sol";
import {TokenDistributor, Action} from "../src/TokenDistributor.sol";

/// @notice Minimal script to configure pools and distribution for NIMPET (PUBLIC)
contract AddNimpetDistribution is Script {
    // Environment-configurable addresses
    address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR_BSC");
    address usdc = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address usdt = 0x55d398326f99059fF775485246999027B3197955;
    address wbnb = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BSC");
    address nimpetTokenAddr = 0x87aa6aEb62ff128aAA96E275d7B24cd12a72ABa1;

    function run() public {
        configurePancakeUSDTToUSDC();
        configurePancakeUSDTToNimpet();
        configurePancakeUSDCToWBNB();
        configurePancakeWBNBToAITV();
        deployNimpetDistribution();
    }

    /// @dev Configure Pancake route USDT <-> USDC (v3 fee=100)
    function configurePancakeUSDTToUSDC() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        vm.startBroadcast();
        uint256 cfgId = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: usdt, tokenB: usdc, fee: 100 })
        );
        distributor.setPancakeConfig(cfgId);
        vm.stopBroadcast();
        console.log("Pancake config USDT <-> USDC set, ID: %s", cfgId);
        return cfgId;
    }

    /// @dev Configure Pancake route USDT <-> NIMPET (v3 fee=100)
    function configurePancakeUSDTToNimpet() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        vm.startBroadcast();
        uint256 cfgId = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: usdt, tokenB: nimpetTokenAddr, fee: 100 })
        );
        distributor.setPancakeConfig(cfgId);
        vm.stopBroadcast();
        console.log("Pancake config USDT <-> NIMPET set, ID: %s", cfgId);
        return cfgId;
    }

    /// @dev Configure Pancake route USDC <-> WBNB (v3 fee=100)
    function configurePancakeUSDCToWBNB() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        vm.startBroadcast();
        uint256 cfgId = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: usdc, tokenB: wbnb, fee: 100 })
        );
        distributor.setPancakeConfig(cfgId);
        vm.stopBroadcast();
        console.log("Pancake config USDC <-> WBNB set, ID: %s", cfgId);
        return cfgId;
    }

    /// @dev Configure Pancake route WBNB <-> AITV (v3 fee=100)
    function configurePancakeWBNBToAITV() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        vm.startBroadcast();
        uint256 cfgId = distributor.proposePancakeConfig(
            PancakeProposal({ tokenA: wbnb, tokenB: aitvTokenAddr, fee: 100 })
        );
        distributor.setPancakeConfig(cfgId);
        vm.stopBroadcast();
        console.log("Pancake config WBNB <-> AITV set, ID: %s", cfgId);
        return cfgId;
    }

    /// @dev Build distribution: 20% to AITV via WBNB, 80% to NIMPET via USDT
    function deployNimpetDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // Sub-distribution: USDT -> NIMPET (100%)
        Action[] memory nimpetChild = new DistributionBuilder()
            .buy(10_000, nimpetTokenAddr, address(0))
            .build();
        vm.startBroadcast();
        uint256 nimpetChildId = distributor.addDistribution(nimpetChild);
        vm.stopBroadcast();

        // Sub-distribution: WBNB -> AITV (100%)
        Action[] memory aitvChild = new DistributionBuilder()
            .buy(10_000, aitvTokenAddr, address(0))
            .build();
        vm.startBroadcast();
        uint256 aitvChildId = distributor.addDistribution(aitvChild);
        vm.stopBroadcast();

        // Parent distribution:
        // - 20%: payment -> WBNB -> AITV
        // - 80%: payment -> USDT -> NIMPET
        Action[] memory parent = new DistributionBuilder()
            .buy(2_000, wbnb, aitvChildId)
            .buy(8_000, usdt, nimpetChildId)
            .build();
        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(parent);
        distributor.setDistributionId("nimpet", distributionId);
        vm.stopBroadcast();

        console.log("NIMPET distribution added, ID: %s", distributionId);
        return distributionId;
    }
}

