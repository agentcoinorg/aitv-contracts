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

contract AddRoastDistributionScript is Script {
    address roastTokenAddr = 0x06fe6D0EC562e19cFC491C187F0A02cE8D5083E4;
    address virtualsTokenAddr = 0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b; 

    function run() public returns (uint256, uint256, uint256) {
        uint256 virtualsWethConfig = proposeVirtualsWethPoolConfig();
        uint256 roastDistId = proposeRoastPoolConfig();

        uint256 burnieDistId = deployRoastDistribution();

        return (virtualsWethConfig, roastDistId, burnieDistId);
    }
     
    function proposeVirtualsWethPoolConfig() public returns (uint256) {
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        address weth = vm.envAddress("WETH");
       
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
        vm.stopBroadcast();

        console.log("VIRTUALS => WETH Pool config proposed, ID: %s", configId);

        return configId;
    }

    function proposeRoastPoolConfig() public returns (uint256) {
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
       
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
        vm.stopBroadcast();

        console.log("ROAST => VIRTUALS Pool config proposed, ID: %s", configId);

        return configId;
    }

    function deployRoastDistribution() public returns (uint256) {
        address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");
        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));
        address weth = vm.envAddress("WETH");

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
        vm.stopBroadcast();

        console.log("TokenDistributor (ROAST) distribution added, ID: %s", distributionId);
    
        return distributionId;
    }
}