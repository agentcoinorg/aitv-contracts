// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {AgentLaunchPool} from "./AgentLaunchPool.sol";
import {AirdropClaim} from "./AirdropClaim.sol";
import {IAgentKey} from "./IAgentKey.sol";


/// @title AgentFactory
/// @notice The following is a contract to deploy agent launch pools
contract AgentFactory is Ownable {

    uint256 public immutable ownerAmount;
    uint256 public immutable agentAmount;
    uint256 public immutable launchPoolAmount;
    uint256 public immutable uniswapPoolAmount;
    address public immutable uniswapRouter;

    event Deployed(address agentLaunchPool);

    constructor(
        address _owner,
        uint256 _ownerAmount,
        uint256 _agentAmount,
        uint256 _launchPoolAmount, 
        uint256 _uniswapPoolAmount, 
        address _uniswapRouter    
    ) Ownable(_owner) {
        ownerAmount = _ownerAmount;
        agentAmount = _agentAmount;
        launchPoolAmount = _launchPoolAmount;
        uniswapPoolAmount = _uniswapPoolAmount;
        uniswapRouter = _uniswapRouter;
    }

    function deploy(
        string memory _name, 
        string memory _symbol, 
        address _agentWallet,
        uint256 _timeWindow,
        uint256 _minAmountForLaunch
    ) external onlyOwner {
        address[] memory recipients = new address[](2);
        recipients[0] = owner();
        recipients[1] = _agentWallet;

        uint256[] memory amounts = new uint256[](2);
        amounts[0] = ownerAmount;
        amounts[1] = agentAmount;

        AgentLaunchPool agentLaunchPool = new AgentLaunchPool(
            owner(),
            _timeWindow,
            _minAmountForLaunch,
            _name,
            _symbol,
            launchPoolAmount,
            uniswapPoolAmount,
            uniswapRouter,
            recipients,
            amounts
        );

        emit Deployed(address(agentLaunchPool));
    }
}