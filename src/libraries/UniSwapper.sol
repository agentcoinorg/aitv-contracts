// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {ActionConstants} from "@uniswap/v4-periphery/src/libraries/ActionConstants.sol";
import {UniswapVersion} from "../types/UniswapVersion.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {PoolConfig} from "../types/PoolConfig.sol";

library UniSwapper {
    error InvalidTokenInOut();

    /// @notice Do an “exact-in” swap on Uniswap V2, V3 or V4 (via Universal Router)
    /// @param _recipient       who gets the `tokenOut`
    /// @param _poolConfig      the pool configuration (pool key and version)
    /// @param _tokenIn         the token you’re selling
    /// @param _tokenOut        the token you want to buy
    /// @param _amountIn        how much of `tokenIn` to sell
    /// @param _amountOutMin    the minimum you’ll accept of `tokenOut`
    /// @param _universalRouter the address of the Uniswap Universal Router contract
    /// @param _permit2         the address of the Permit2 contract
    /// @return amountOut      how many `tokenOut` landed in `recipient`
    function swapExactIn(
        address _recipient,
        PoolConfig memory _poolConfig,
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint128 _amountOutMin,
        uint256 _deadline,
        IUniversalRouter _universalRouter,
        IPermit2 _permit2
    ) internal returns (uint256 amountOut) {
        uint256 startBal = _tokenOut == address(0) 
            ? address(_recipient).balance
            : IERC20(_tokenOut).balanceOf(_recipient);

        if (_tokenIn != address(0)) {
            if (IERC20(_tokenIn).allowance(address(this), address(_permit2)) < _amountIn) {
                IERC20(_tokenIn).approve(address(_permit2), type(uint256).max);
            }

            IPermit2(_permit2).approve(_tokenIn, address(_universalRouter), uint160(_amountIn), uint48(_deadline) + 1); // +1 because expiration is "The timestamp at which the approval is no longer valid"
        }

        bytes memory commands = abi.encodePacked(
            _poolConfig.version == UniswapVersion.V2 ? uint8(Commands.V2_SWAP_EXACT_IN) :
            _poolConfig.version == UniswapVersion.V3 ? uint8(Commands.V3_SWAP_EXACT_IN) :
                                     uint8(Commands.V4_SWAP)
        );

        bytes[] memory inputs = new bytes[](1);

        if (_poolConfig.version == UniswapVersion.V2) {
            address[] memory path = new address[](2);
            path[0] = _tokenIn;
            path[1] = _tokenOut;
            inputs[0] = abi.encode(
              ActionConstants.MSG_SENDER,
              _amountIn,
              _amountOutMin,
              path,
              true
            );
        } else if (_poolConfig.version == UniswapVersion.V3) {
            bytes memory path = abi.encodePacked(_tokenIn, uint24(_poolConfig.poolKey.fee), _tokenOut);
            inputs[0] = abi.encode(
                _recipient,
                _amountIn,
                _amountOutMin,
                path,
                true
            );
        } else {
            bool zeroForOne;

            if (_tokenIn == Currency.unwrap(_poolConfig.poolKey.currency0) && _tokenOut == Currency.unwrap(_poolConfig.poolKey.currency1)) {
                zeroForOne = true;
            } else if (_tokenIn == Currency.unwrap(_poolConfig.poolKey.currency1) && _tokenOut == Currency.unwrap(_poolConfig.poolKey.currency0)) {
                zeroForOne = false;
            } else {
                revert InvalidTokenInOut();
            }

            bytes memory swapExactSingleParams = abi.encode(
                IV4Router.ExactInputSingleParams({
                    poolKey: _poolConfig.poolKey,
                    zeroForOne: zeroForOne,
                    amountIn: uint128(_amountIn),
                    amountOutMinimum: _amountOutMin,
                    hookData: bytes("")
                })
            );

            bytes memory actions = abi.encodePacked(
                uint8(Actions.SWAP_EXACT_IN_SINGLE),
                uint8(Actions.SETTLE_ALL),
                uint8(Actions.TAKE_ALL)
            );

            bytes[] memory params = new bytes[](3);
            
            params[0] = swapExactSingleParams;
            
            params[1] = abi.encode(_tokenIn, uint128(_amountIn));
            params[2] = abi.encode(_tokenOut, _amountOutMin);

            inputs[0] = abi.encode(actions, params);
        }

        _universalRouter.execute{ value: (_tokenIn == address(0) ? _amountIn : 0) }(
            commands,
            inputs,
            _deadline
        );

        uint256 endBal = _tokenOut == address(0)
            ? address(_recipient).balance 
            : IERC20(_tokenOut).balanceOf(_recipient);
        
        return endBal - startBal;
    }
}
