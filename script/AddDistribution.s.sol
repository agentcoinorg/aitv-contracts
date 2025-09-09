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

contract AddDistributionScript is Script {
    function run() public returns (uint256, uint256, uint256, uint256, uint256) {
        (uint256 configId1, uint256 configId2, uint256 configId3) = proposePoolConfigs();
        uint256 viladyDistId = deployViladyDistribution();
        uint256 geckoDistId = deployGeckoDistribution();

        return (configId1, configId2, configId3, viladyDistId, geckoDistId);
    }

    function proposePoolConfigs() public returns (uint256, uint256, uint256) {
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        address weth = vm.envAddress("WETH");
        address geckoTokenAddr = 0x452867Ec20dC5061056C1613db2801f512dDa1C1;
        address viladyTokenAddr = 0x0deE1df0F634dF4792E76816b42002fB2a97c432;
        address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        
        // USDC => WETH
        vm.startBroadcast();
        uint256 configId1 = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(usdc),
                    fee: 500, // 0.05% fee
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );
        vm.stopBroadcast();
        console.log("USDC => WETH Pool config proposed, ID: %s", configId1);

        // ETH => VILADY - Uniswap V4
        vm.startBroadcast();
        uint256 configId2 = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(address(0)),
                    currency1: Currency.wrap(viladyTokenAddr),
                    fee: 0,
                    tickSpacing: 200,
                    hooks: IHooks(address(0x10c1b4C7b1ac62A0F83458F342C3d6B8D2847fff))
                }),
                version: UniswapVersion.V4
            })
        );
        vm.stopBroadcast();
        console.log("ETH => VILADY Pool config proposed, ID: %s", configId2);

        // WETH => GECKO - Uniswap V2
        vm.startBroadcast();
        uint256 configId3 = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(geckoTokenAddr),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
        vm.stopBroadcast();
        console.log("WETH => GECKO Pool config proposed, ID: %s", configId3);

        return (configId1, configId2, configId3);
    }

    function deployViladyDistribution() public returns (uint256) {
        address viladyTokenAddr = 0x0deE1df0F634dF4792E76816b42002fB2a97c432;

        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_OWNER");
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
            .send(1_000, owner)
            .buy(9_000, weth, subDistId2)
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions3);
        vm.stopBroadcast();

        console.log("TokenDistributor (VILADY) distribution added, ID: %s", distributionId);

        return distributionId;
    }

    function deployGeckoDistribution() public returns (uint256) {
        address geckoTokenAddr = 0x452867Ec20dC5061056C1613db2801f512dDa1C1;
        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_OWNER");
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
            .buy(9_000, weth, subDistId2)
            .send(1_000, owner)
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions3);
        vm.stopBroadcast();

        console.log("TokenDistributor (GECKO) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }
}