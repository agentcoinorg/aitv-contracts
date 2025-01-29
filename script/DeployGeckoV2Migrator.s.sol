// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {GeckoV2Migrator} from "../src/GeckoV2Migrator.sol";

contract DeployGeckoV2Migrator is Script {
    function setUp() public {}

    function run() public {
        deploy();
    }

    function deploy() public  {
        address geckoV1TokenAddress = vm.envAddress("GECKO_V1_TOKEN_ADDRESS");
        address geckoWalletAddress = vm.envAddress("GECKO_WALLET_ADDRESS");
        address daoAddress = vm.envAddress("DAO_ADDRESS");
        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");

        uint256 agentAmount = 300_000 * 1e18;
        uint256 daoAmount = 700_000 * 1e18;
        uint256 airdropAmount = 2_500_000 * 1e18;
        uint256 poolAmount = 6_500_000 * 1e18;

        vm.startBroadcast();

        new GeckoV2Migrator(daoAddress, "Agent Gecko TV", "GECKO", daoAddress, geckoWalletAddress, daoAmount, agentAmount, airdropAmount, poolAmount, geckoV1TokenAddress, uniswapRouter);

        vm.stopBroadcast();
    }
}
