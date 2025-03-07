// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { HookMiner } from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import { Hooks } from '@uniswap/v4-core/src/libraries/Hooks.sol';
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentUniswapHook} from "./AgentUniswapHook.sol";

abstract contract AgentUniswapHookDeployer {
    function _deployAgentUniswapHook(address _owner, address _controller, address _uniswapPoolManager) internal returns(AgentUniswapHook) {
        AgentUniswapHook implementation = new AgentUniswapHook();

        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG
        );

        bytes memory data = abi.encodeCall(AgentUniswapHook.initialize, (_owner, _controller, _uniswapPoolManager));

        bytes memory constructorArgs = abi.encode(implementation, data);
        (address foundAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(ERC1967Proxy).creationCode, constructorArgs);

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(address(implementation), data);

        require(address(proxy) == foundAddress, "Deployed address does not match");

        return AgentUniswapHook(foundAddress);
    }
}