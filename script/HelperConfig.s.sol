// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

abstract contract Constants {
    uint256 public constant CHAIN_ID_BASE = 8453;
    uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
}

contract HelperConfig is Constants, Script {
    struct AgentKeyConfig {
        string name;
        string symbol;
        uint256 priceIncrease;
        uint256 investmentReserveBasisPoints;
        uint feeBasisPoints;
        uint revenueCommitmentBasisPoints;
        address payable beneficiary;
        address control;
        address payable feeCollector;
    }

    function getConfig() public view returns (AgentKeyConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) private view returns (AgentKeyConfig memory) {
        if (chainId == CHAIN_ID_BASE_SEPOLIA) {
            return getBaseSepoliaConfig();
        } else if (chainId == CHAIN_ID_BASE) {
            return getBaseConfig();
        } else {
            revert("Unsupported chain id");
        }
    }

    function getBaseConfig() private view returns (AgentKeyConfig memory) {
        return AgentKeyConfig({
            name: vm.envString("BASE_TOKEN_NAME"),
            symbol: vm.envString("BASE_TOKEN_SYMBOL"),
            priceIncrease: vm.envUint("BASE_PRICE_INCREASE"),
            investmentReserveBasisPoints: 9000,
            beneficiary: payable(vm.envAddress("BASE_BENEFICIARY")),
            control: vm.envAddress("BASE_CONTROL"),
            feeCollector: payable(vm.envAddress("BASE_FEE_COLLECTOR")),
            feeBasisPoints: 5000,
            revenueCommitmentBasisPoints: 9500
        });
    }

    function getBaseSepoliaConfig() private view returns (AgentKeyConfig memory) {
        return AgentKeyConfig({
            name: vm.envString("BASE_SEPOLIA_TOKEN_NAME"),
            symbol: vm.envString("BASE_SEPOLIA_TOKEN_SYMBOL"),
            priceIncrease: vm.envUint("BASE_SEPOLIA_PRICE_INCREASE"),
            investmentReserveBasisPoints: 9000,
            beneficiary: payable(vm.envAddress("BASE_SEPOLIA_BENEFICIARY")),
            control: vm.envAddress("BASE_SEPOLIA_CONTROL"),
            feeCollector: payable(vm.envAddress("BASE_SEPOLIA_FEE_COLLECTOR")),
            feeBasisPoints: 5000,
            revenueCommitmentBasisPoints: 9500
        });
    }
}