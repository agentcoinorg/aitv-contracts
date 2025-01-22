// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {GeckoKeyV2} from "./../src/GeckoKeyV2.sol";

contract DeployGeckoKeyV2 is Script {
    function setUp() public {}

    function run() public {
        HelperConfig helper = new HelperConfig();

        deploy(helper.getConfig());
    }

    function deploy(HelperConfig.AgentKeyConfig memory config) public returns(address) {
        address geckoV1TokenAddress = vm.envAddress("GECKO_V1_TOKEN_ADDRESS");
        address agentcoinDaoAddress = vm.envAddress("AGENTCOIN_DAO_ADDRESS");
        address poolAddress = vm.envAddress("POOL_ADDRESS");
        
        vm.startBroadcast();

        GeckoKeyV2 implementation = new GeckoKeyV2();

        address[] memory recipients = new address[](2);
        recipients[0] = agentcoinDaoAddress;
        recipients[1] = poolAddress;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1_000_000;
        amounts[2] = 8_000_000;

        uint256 airdropAmount = 1_000_000;

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implementation), abi.encodeCall(AgentKeyV2.initialize, ("Gecko", "GECKO", config.owner, recipients, amounts, geckoV1TokenAddress, airdropAmount))
        );

        vm.stopBroadcast();

        address geckoV2Address = address(proxy);

        return geckoV2Address;
    }
}
