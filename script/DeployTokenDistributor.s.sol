// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {TokenDistributor} from "../src/TokenDistributor.sol";

contract DeployTokenDistributorScript is Script {
    function run() public {
        address owner = vm.envAddress("TOKEN_DISTRIBUTOR_OWNER");
        address uniswapUniversalRouter = vm.envAddress("BASE_UNIVERSAL_ROUTER");
        address permit2 = vm.envAddress("PERMIT2");
        address weth = vm.envAddress("WETH");

        vm.startBroadcast();
        TokenDistributor impl = new TokenDistributor();
        vm.stopBroadcast();

        console.log("TokenDistributor implementation deployed at %s", address(impl));
        
        vm.startBroadcast();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl), abi.encodeCall(TokenDistributor.initialize, (owner, IUniversalRouter(uniswapUniversalRouter), IPermit2(permit2), weth))
        );
        vm.stopBroadcast();

        console.log("TokenDistributor proxy deployed at %s", address(proxy));

        TokenDistributor distributor = TokenDistributor(payable(address(proxy)));

        require(owner == distributor.owner(), "Owner mismatch");
        require(uniswapUniversalRouter == address(distributor.uniswapUniversalRouter()), "UniswapUniversalRouter mismatch");
        require(permit2 == address(distributor.permit2()), "Permit2 mismatch");
        require(weth == address(distributor.weth()), "WETH mismatch");
    }
}
