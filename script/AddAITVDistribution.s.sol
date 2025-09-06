// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";

import {PoolConfig} from "../src/types/PoolConfig.sol";
import {UniswapVersion} from "../src/types/UniswapVersion.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {DistributionBuilder} from "../src/DistributionBuilder.sol";
import {TokenDistributor, Action} from "../src/TokenDistributor.sol";

contract AddAITVDistributionScript is Script {
    function run() public returns (uint256, uint256, uint256) {
        uint256 aitvUsdcConfig = proposeAITVPoolConfig();
        uint256 viladyDistId = deployViladyDistribution();
        uint256 geckoDistId = deployGeckoDistribution();

        return (aitvUsdcConfig, viladyDistId, geckoDistId);
    }

    function proposeAITVPoolConfig() public returns (uint256) {
        address usdc = vm.envAddress("USDC_BASE");
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
       
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // USDC => AITV
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(aitvTokenAddr),
                    currency1: Currency.wrap(usdc),
                    fee: 3000, // 0.3% fee
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );
        vm.stopBroadcast();

        console.log("AITV => USDC Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployViladyDistribution() public returns (uint256) {
        address viladyTokenAddr = 0x0deE1df0F634dF4792E76816b42002fB2a97c432;
        address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        address weth = vm.envAddress("WETH");

        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions1= new DistributionBuilder()
            .buy(10_000, viladyTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 subDistId1 = distributor.addDistribution(actions1);
        vm.stopBroadcast();

        Action[] memory actions2 = new DistributionBuilder()
            .buy(10_000, address(0), subDistId1)
            .build();

        vm.startBroadcast();
        uint256 subDistId2 = distributor.addDistribution(actions2);
        vm.stopBroadcast();

        Action[] memory actions3 = new DistributionBuilder()
            .buy(2_000, aitvTokenAddr, address(0))
            .buy(8_000, weth, subDistId2)
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions3);
        vm.stopBroadcast();

        console.log("TokenDistributor (VILADY) distribution added, ID: %s", distributionId);

        return distributionId;
    }

    function deployGeckoDistribution() public returns (uint256) {
        address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
        address geckoTokenAddr = 0x452867Ec20dC5061056C1613db2801f512dDa1C1;
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        address weth = vm.envAddress("WETH");

        Action[] memory actions1 = new DistributionBuilder()
            .send(9_000, address(0))
            .send(1_000, address(0x000000000000000000000000000000000000dEaD))
            .build();

        vm.startBroadcast();
        uint256 subDistId1 = distributor.addDistribution(actions1);
        vm.stopBroadcast();

        Action[] memory actions2 = new DistributionBuilder()
            .buy(10_000, geckoTokenAddr, subDistId1)
            .build();

        vm.startBroadcast();
        uint256 subDistId2 = distributor.addDistribution(actions2);
        vm.stopBroadcast();

        Action[] memory actions3 = new DistributionBuilder()
            .buy(2_000, aitvTokenAddr, address(0))
            .buy(8_000, weth, subDistId2)
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions3);
        vm.stopBroadcast();

        console.log("TokenDistributor (GECKO) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }
}