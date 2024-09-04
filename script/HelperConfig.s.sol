// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

abstract contract Constants {
    uint256 public constant CHAIN_ID_LOCAL = 31337;
    uint256 public constant CHAIN_ID_BASE_SEPOLIA = 84532;
}

contract HelperConfig is Constants, Script {
    struct AgentKeyConfig {
        uint256 buySlopeNum;
        uint256 buySlopeDen;
        uint256 investmentReserveBasisPoints;
        uint feeBasisPoints;
        uint revenueCommitmentBasisPoints;
        address payable beneficiary;
        address control;
        address payable feeCollector;
    }

    AgentKeyConfig public localAgentKeyConfig;
    mapping (uint256 chainId => AgentKeyConfig) public agentKeyConfigs;

    constructor() {
        agentKeyConfigs[CHAIN_ID_LOCAL] = getLocalAnvilConfig();
        agentKeyConfigs[CHAIN_ID_BASE_SEPOLIA] = getBaseSepoliaConfig();
    }

    function getConfig() public view returns (AgentKeyConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) private view returns (AgentKeyConfig memory) {
        return agentKeyConfigs[chainId];
    }

    function getLocalAnvilConfig() private pure returns (AgentKeyConfig memory) {
        return AgentKeyConfig({
            buySlopeNum: 2,
            buySlopeDen: 10000 * 1e18,
            investmentReserveBasisPoints: 9500,
            // First address derived from mnemonic: test test test test test test test test test test test junk
            beneficiary: payable(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266),
            // Second address
            control: address(0x70997970C51812dc3A010C7d01b50e0d17dc79C8),
            // Third address
            feeCollector: payable(0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC),
            feeBasisPoints: 1000,
            revenueCommitmentBasisPoints: 9500
        });
    }

    function getBaseSepoliaConfig() private pure returns (AgentKeyConfig memory) {
        return AgentKeyConfig({
            buySlopeNum: 2,
            buySlopeDen: 10000 * 1e18,
            investmentReserveBasisPoints: 9500,
            beneficiary: payable(0x857766085629c1d68704989974A968cbdbf2fc3f),
            control: 0x857766085629c1d68704989974A968cbdbf2fc3f,
            feeCollector: payable(0x857766085629c1d68704989974A968cbdbf2fc3f),
            feeBasisPoints: 1000,
            revenueCommitmentBasisPoints: 9500
        });
    }
}