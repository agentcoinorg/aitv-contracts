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
    function run() public {
        deployAITVDistribution();
    }

    function deployAITVDistribution() public returns (uint256) {
        address aitvTokenAddr = vm.envAddress("AITV_TOKEN_BASE");
        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_OWNER");
        address distributorAddr = vm.envAddress("TOKEN_DISTRIBUTOR");

        TokenDistributor distributor = TokenDistributor(payable(distributorAddr));

        Action[] memory actions = new DistributionBuilder()
            .send(1_000, owner)
            .buy(9_000, aitvTokenAddr, address(0))
            .build();

        vm.startBroadcast();
        uint256 distributionId = distributor.addDistribution(actions);
        vm.stopBroadcast();

        console.log("AITV only distribution added, ID: %s", distributionId);

        return distributionId;
    }
}