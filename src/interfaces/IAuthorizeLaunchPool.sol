// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IAuthorizeLaunchPool {
    /// @notice Set whether a launch pool is authorized to use the uniswap hook
    function setAuthorizedLaunchPool(address _launchPool, bool _isAuthorized) external;
}
