// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IAerodromeRouter} from "../src/interfaces/IAerodromeRouter.sol";
import {TokenDistributor} from "../src/TokenDistributor.sol";

contract DeployTokenDistributorScript is Script {
    function run() public {
        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_OWNER");
        address uniswapUniversalRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");
        address permit2 = vm.envAddress("PERMIT2");
        address weth = vm.envAddress("WETH");
        address aerodromeRouter = vm.envAddress("AERODROME_ROUTER");

        vm.startBroadcast();
        TokenDistributor distributor = new TokenDistributor(
            owner,
            IUniversalRouter(uniswapUniversalRouter),
            IPermit2(permit2),
            weth,
            IAerodromeRouter(aerodromeRouter)
        );
        vm.stopBroadcast();

        console.log("TokenDistributor deployed at %s", address(distributor));

        require(owner == distributor.owner(), "Owner mismatch");
        require(uniswapUniversalRouter == address(distributor.uniswapUniversalRouter()), "UniswapUniversalRouter mismatch");
        require(permit2 == address(distributor.permit2()), "Permit2 mismatch");
        require(weth == address(distributor.weth()), "WETH mismatch");
        require(aerodromeRouter == address(distributor.aerodromeRouter()), "AerodromeRouter mismatch");
    }
}
