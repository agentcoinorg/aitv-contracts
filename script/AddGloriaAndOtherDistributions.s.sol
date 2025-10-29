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

contract AddGloriaAndOtherDistributions is Script {
    address virtualsTokenAddr = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; 
    address usdc = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
    address weth = vm.envAddress("WETH");
    address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
    address gloriaTokenAddr = 0x3B313f5615Bbd6b200C71f84eC2f677B94DF8674;
    address eolasTokenAddr = 0xF878e27aFB649744EEC3c5c0d03bc9335703CFE3;
    address nimpetTokenAddr = 0x2a06A17CBC6d0032Cac2c6696DA90f29D39a1a29;
    address pettbroTokenAddr = 0x02D4f76656C2B4f58430e91f8ac74896c9281Cb9;

    function run() public {
        proposeGloriaPoolConfig();
        proposeEolasPoolConfig();
        proposeNimpetPoolConfig();
        deployGloriaDistribution();
        deployEolasDistribution();
        deployNimpetDistribution();
    }

    function proposeGloriaPoolConfig() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // GLORIA => VIRTUALS - Uniswap V2
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(virtualsTokenAddr),
                    currency1: Currency.wrap(gloriaTokenAddr),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
        
        vm.stopBroadcast();
        console.log("GLORIA => VIRTUALS Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployGloriaDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions1 = new DistributionBuilder()
            .buy(10_000, gloriaTokenAddr, address(0))
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
        vm.stopBroadcast();
        console.log("TokenDistributor (GLORIA) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }

    function proposeEolasPoolConfig() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // GLORIA => VIRTUALS - Uniswap V2
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(weth),
                    currency1: Currency.wrap(eolasTokenAddr),
                    fee: 0,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V2
            })
        );
        
        vm.stopBroadcast();
        console.log("EOLAS => WETH Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployEolasDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions1 = new DistributionBuilder()
            .buy(10_000, eolasTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 subDistId1 = distributor.addDistribution(actions1);
        vm.stopBroadcast();

        Action[] memory actions2 = new DistributionBuilder()
            .buy(2_000, aitvTokenAddr, address(0))
            .buy(8_000, weth, subDistId1)
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions2);
        vm.stopBroadcast();

        console.log("TokenDistributor (Eolas) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }

    function proposeNimpetPoolConfig() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        // Nimpet => USDC - Uniswap V3
        vm.startBroadcast();
        uint256 configId = distributor.proposePoolConfig(
            PoolConfig({
                poolKey: PoolKey({
                    currency0: Currency.wrap(nimpetTokenAddr),
                    currency1: Currency.wrap(usdc),
                    fee: 10000,
                    tickSpacing: 0,
                    hooks: IHooks(address(0))
                }),
                version: UniswapVersion.V3
            })
        );
        
        vm.stopBroadcast();
        console.log("Nimpet => USDC Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployNimpetDistribution() public returns (uint256) {
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions1 = new DistributionBuilder()
            .buy(2_000, aitvTokenAddr, address(0))
            .buy(8_000, nimpetTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions1);
        vm.stopBroadcast();

        console.log("TokenDistributor (Nimpet) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }
}