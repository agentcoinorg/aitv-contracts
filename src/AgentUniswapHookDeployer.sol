// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {HookMiner} from "@uniswap/v4-periphery/src/utils/HookMiner.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {AgentUniswapHook} from "./AgentUniswapHook.sol";

/// @title AgentUniswapHookDeployer
/// @notice The following is a contract to deploy agent uniswap hooks
/// @dev It mines the salt for the proxy contract and deploys the hook
/// All flags are set to true, so that we can use any hook function if we upgrade the hook in the future
abstract contract AgentUniswapHookDeployer {
    function _deployAgentUniswapHook(address _owner, address _controller, address _uniswapPoolManager, address _hookImpl) internal returns(AgentUniswapHook) {
        uint160 flags = Hooks.ALL_HOOK_MASK;

        bytes memory data = abi.encodeCall(AgentUniswapHook.initialize, (_owner, _controller, _uniswapPoolManager));

        bytes memory constructorArgs = abi.encode(_hookImpl, data);
        (address foundAddress, bytes32 salt) =
            HookMiner.find(address(this), flags, type(ERC1967Proxy).creationCode, constructorArgs);

        ERC1967Proxy proxy = new ERC1967Proxy{salt: salt}(_hookImpl, data);

        require(address(proxy) == foundAddress, "Deployed address does not match");

        return AgentUniswapHook(foundAddress);
    }
}