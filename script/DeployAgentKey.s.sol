// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {IAgentKey} from "./../src/IAgentKey.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {AgentKeyWhitelist} from "./../src/AgentKeyWhitelist.sol";

contract DeployAgentKey is Script {
    function setUp() public {}

    function run() public {
        HelperConfig helper = new HelperConfig();

        deploy(helper.getConfig());
    }

    function deploy(HelperConfig.AgentKeyConfig memory config) public returns (IAgentKey key, address whitelist) {
        {
            // buySlopeNum and buySlopeDen are used for the formula in: https://github.com/Fairmint/c-org/blob/781d1ed8d70d733eed57c5e7fff8931b096de0e9/contracts/ContinuousOffering.sol#L495
            bytes memory ctorArgs = abi.encode(
                0 ether, // initReserve
                address(0), // currencyAddress
                0, // initGoal
                2, // buySlopeNum
                50000000 * config.priceIncrease, // buySlopeDen
                config.investmentReserveBasisPoints,
                0, // setupFee
                payable(address(0)), // setupFeeRecipient
                config.name,
                config.symbol
            );

            vm.startBroadcast();

            key = IAgentKey(deployCode("AgentKey.sol:AgentKey", ctorArgs));
        }

        whitelist = address(new AgentKeyWhitelist());

        key.updateConfig(
            whitelist,
            config.beneficiary,
            config.control,
            config.feeCollector,
            config.feeBasisPoints,
            config.revenueCommitmentBasisPoints,
            1, // minInvestment
            0 // minDuration
        );

        vm.stopBroadcast();

        return (key, whitelist);
    }
}
