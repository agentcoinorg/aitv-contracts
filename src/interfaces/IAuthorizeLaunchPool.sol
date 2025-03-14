// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


interface IAuthorizeLaunchPool {
    function setAuthorizedLaunchPool(address _launchPool, bool _isAuthorized) external;
}
