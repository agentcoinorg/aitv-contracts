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

    function deploy(
        HelperConfig.AgentKeyConfig memory config
    ) public returns (IAgentKey key, address whitelist) {
        {
            uint256 initReserve = 0 ether;
            address currencyAddress = address(0);
            uint256 initGoal = 0;
            uint256 setupFee = 0;
            address payable setupFeeRecipient = payable(address(0));
            string memory name = "Agent Keys";
            string memory symbol = "KEYS";

            bytes memory ctorArgs = abi.encode(
                initReserve,
                currencyAddress,
                initGoal,
                config.buySlopeNum,
                config.buySlopeDen,
                config.investmentReserveBasisPoints,
                setupFee,
                setupFeeRecipient,
                name,
                symbol
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
            1,
            0
        );

        vm.stopBroadcast();

        return (key, whitelist);
    }
}
