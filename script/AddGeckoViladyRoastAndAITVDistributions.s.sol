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
    address roastTokenAddr = 0x06fe6D0EC562e19cFC491C187F0A02cE8D5083E4;
    address virtualsTokenAddr = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; 
    address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
    address weth = vm.envAddress("WETH");
    address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
    address geckoTokenAddr = 0x452867Ec20dC5061056C1613db2801f512dDa1C1;
    address viladyTokenAddr = 0x0deE1df0F634dF4792E76816b42002fB2a97c432;

    function run() public {
        proposePoolConfigs();
        proposeVirtualsWethPoolConfig();
        proposeRoastPoolConfig();
        proposeAITVPoolConfig();
        deployViladyDistribution();
        deployRoastDistribution();
        deployGeckoDistribution();
        deployAITVDistribution();
    
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        vm.startBroadcast();
        distributor.transferOwnership(0xeff5440746A7B362273ca7CDDB9CD5783C71737D);
        vm.stopBroadcast();

        console.log("TokenDistributor ownership transferred to %s", 0xeff5440746A7B362273ca7CDDB9CD5783C71737D);
    }

    function proposePoolConfigs() public returns (uint256, uint256, uint256) {
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
        distributor.setPoolConfig(configId1);
        
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
        distributor.setPoolConfig(configId2);
    
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
        distributor.setPoolConfig(configId3);
        
        vm.stopBroadcast();
        console.log("WETH => GECKO Pool config proposed, ID: %s", configId3);

        return (configId1, configId2, configId3);
    }

    function proposeAITVPoolConfig() public returns (uint256) {       
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
        distributor.setPoolConfig(configId);
        vm.stopBroadcast();

        console.log("AITV => USDC Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployViladyDistribution() public returns (uint256) {
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
        distributor.setDistributionId("vilady", distributionId);
        vm.stopBroadcast();

        console.log("TokenDistributor (VILADY) distribution added, ID: %s", distributionId);

        return distributionId;
    }

    function deployGeckoDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

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
        distributor.setDistributionId("gecko", distributionId);
        vm.stopBroadcast();

        console.log("TokenDistributor (GECKO) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }

    function proposeVirtualsWethPoolConfig() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // WETH => VIRTUALS
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(virtualsTokenAddr),
                    currency1: Currency.wrap(weth),
                    fee: 3000, // 0.3% fee
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
        distributor.setPoolConfig(configId);
        vm.stopBroadcast();

        console.log("VIRTUALS => WETH Pool config proposed, ID: %s", configId);

        return configId;
    }

    function proposeRoastPoolConfig() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // ROAST => VIRTUALS
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(roastTokenAddr),
                    currency1: Currency.wrap(virtualsTokenAddr),
                    fee: 3000, // 0.3% fee
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
        distributor.setPoolConfig(configId);
        vm.stopBroadcast();

        console.log("ROAST => VIRTUALS Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployRoastDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions1 = new DistributionBuilder()
            .buy(10_000, roastTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 subDistId1 = distributor.addDistribution(actions1);
        vm.stopBroadcast();

        Action[] memory actions2 = new DistributionBuilder()
            .buy(10_000, virtualsTokenAddr, subDistId1)
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
        distributor.setDistributionId("burnie", distributionId);
        vm.stopBroadcast();

        console.log("TokenDistributor (ROAST) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }

    function deployAITVDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions = new DistributionBuilder()
            .buy(10_000, aitvTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions);
        distributor.setDistributionId("aitv", distributionId);
        vm.stopBroadcast();

        console.log("AITV only distribution added, ID: %s", distributionId);

        return distributionId;
    }
}