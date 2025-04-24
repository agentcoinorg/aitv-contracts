// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IUniversalRouter} from "@uniswap/universal-router/src/interfaces/IUniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/src/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";

enum ActionType {
    Burn,
    Send,
    Buy,
    SendAndCall,
    SendAndCallForBeneficiary
}

struct Action {
    ActionType actionType;
    uint256 dataIndex;
}

struct BurnData {
    uint256 basisAmount;
}

struct SendData {
    address recipient;
    uint256 basisAmount;
}

struct BuyData {
    address tokenToBuy;
    uint256 basisAmount;
    uint256 distributionId;
}

struct SendAndCall {
    address recipient;
    uint256 basisAmount;
    bytes4 signature;
    address recipientOnFailure;
}

struct SendAndCallForBeneficiary {
    address recipient;
    uint256 basisAmount;
    bytes4 signature;
    address recipientOnFailure;
}

struct Distribution {
    PoolKey poolKey;
    Action[] actions;
    BurnData[] burns;
    SendData[] sends;
    BuyData[] buys;
    SendAndCall[] sendAndCalls;
    SendAndCallForBeneficiary[] sendAndCallForBeneficiary;
}

struct PromptPaymentInfo {
    uint256 distributionId;
    
}

/// @title Prompter
contract Prompter is Ownable2StepUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address payable;
    
    error LengthMismatch();
    error ZeroAddressNotAllowed();
    error InvalidETHValue();
    error PaymentInfoNotFound();
    error SendAndCallFailed();
    error SendAndCallForBeneficiaryFailed();
    error DistributionNotFound();
    error ZeroAmountNotAllowed();
    error BurningETHNotAllowed();

    IPoolManager public poolManager;
    IPositionManager public positionManager;
    address public universalRouter;

    mapping(bytes32 => uint256) internal promptDistributionIds;
    mapping(uint256 => Distribution) internal distributions;
    mapping(address => PoolKey) internal poolKeys;
    uint256 internal lastDistributionId;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function setPoolKey(
        address token,
        PoolKey calldata poolKey
    ) external virtual onlyOwner {
        if (token == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        poolKeys[token] = poolKey;
    }

    function addDistribution(
        Distribution calldata distribution
    ) external virtual returns(uint256 distributionId) {
        if (distribution.actions.length != distribution.burns.length + distribution.sends.length + distribution.buys.length + distribution.sendAndCalls.length + distribution.sendAndCallForBeneficiary.length) {
            revert LengthMismatch();
        }

        distributionId = lastDistributionId + 1;
        lastDistributionId++;
        distributions[distributionId] = distribution;

        return distributionId;
    }

    function updateDistribution(
        uint256 distributionId,
        Distribution calldata distribution
    ) external virtual onlyOwner {
        if (distributionId == 0) {
            revert("Zero Id Not Allowed");
        }

        if (distribution.actions.length !=  distribution.burns.length + distribution.sends.length + distribution.buys.length + distribution.sendAndCalls.length + distribution.sendAndCallForBeneficiary.length) {
            revert LengthMismatch();
        }

        distributions[distributionId] = distribution;
    }


    function setPromptPaymentInfo(bytes32 promptType, uint256 distributionId) external virtual onlyOwner returns(uint256) {
        if (agentToken == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        if (distribution.actions.length != distribution.burns.length + distribution.sends.length + distribution.buys.length + distribution.sendAndCalls.length + distribution.sendAndCallForBeneficiary.length) {
            revert LengthMismatch();
        }

        promptDistributionIds[promptType] = distributionId;

        return distributionId;
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract and the one who can upgrade it
    /// @param _uniswapPoolManager The address of the uniswap pool manager
    /// @param _positionManager The address of the position manager
    function initialize(
        address _owner,
        address _uniswapPoolManager,
        address _positionManager,
        address _universalRouter
    ) external initializer {
        if (_uniswapPoolManager == address(0) || _positionManager == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __Ownable_init(_owner); // Checks for zero address
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        poolManager = IPoolManager(_uniswapPoolManager);
        positionManager = IPositionManager(_positionManager);
        universalRouter = _universalRouter;
    }

    function promptWithETH(
        bytes32 _promptType, 
        address _beneficiary
    ) external payable {
        uint256 amount = msg.value;

        if (amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        uint256 distributionId = promptDistributionIds[_promptType];

        _execDistribution(distributionId, _amount, address(0), uint256(uint160(_beneficiary)));
    }

    function promptWithERC20(bytes32 _promptType, address _beneficiary, uint256 _amount, address _paymentToken) external {
        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 distributionId = agentDistributionIds[_promptType];

        _execDistribution(distributionId, _amount, _paymentToken, uint256(uint160(_beneficiary)));
    }

    function _execDistribution(uint256 _distributionId, address _beneficiary, uint256 _amount, address _paymentToken) internal {
        if (_distributionId == 0) {
            revert DistributionNotFound();
        }

        Distribution memory distribution = distributions[_distributionId];
        uint256 actionCount = distribution.actions.length;
        
        for (uint256 i = 0; i < actionCount; i++) {
            Action memory action = distribution.actions[i];

            if (action.actionType == ActionType.Burn) {
                BurnData memory data = distribution.burns[action.dataIndex];
                uint256 amountToBurn = (_amount * data.basisAmount) / 10000;

                if (_paymentToken == address(0)) {
                    revert BurningETHNotAllowed();
                } else {
                    IBurnable(_paymentToken).burn(amountToBurn);
                }
            } else if (action.actionType == ActionType.Send) {
                SendData memory data = distribution.sends[action.dataIndex];
                uint256 amountToSend = (_amount * data.basisAmount) / 10000;

                if (_paymentToken == address(0)) {
                    payable(data.recipient).sendValue(amountToSend);
                } else {
                    IERC20(_paymentToken).safeTransfer(data.recipient, amountToSend);
                }

            } else if (action.actionType == ActionType.Buy) {
                BuyData memory data = distribution.buys[action.dataIndex];
                uint256 amountToSwap = (_amount * data.basisAmount) / 10000;
                uint256 amountOut = _swapETHForERC20ExactIn(amountToSwap, distribution.poolKey);

                _execDistribution(data.distributionId, amountOut, data.tokenToBuy, _beneficiary);

            } else if (action.actionType == ActionType.SendAndCall) {
                SendAndCall memory data = distribution.sendAndCalls[action.dataIndex];
                uint256 amountToSend = (_amount * data.basisAmount) / 10000;

                if (_paymentToken == address(0)) {
                    bytes memory callData = abi.encodeWithSelector(data.signature);

                   (bool success, ) = data.recipient.call{value: amountToSend}(callData);

                    if (!success && data.recipientOnFailure != address(0)) {
                        payable(data.recipientOnFailure).sendValue(amountToSend);
                    } else if (!success) {
                        revert SendAndCallFailed();
                    }
                } else {
                    IERC20(_paymentToken).approve(data.recipient, amountToSend);
                
                    bytes memory callData = abi.encodeWithSelector(
                        data.signature,
                        amountToSend
                    );

                   (bool success, ) = data.recipient.call(callData);

                    if (!success && data.recipientOnFailure != address(0)) {
                        IERC20(_paymentToken).safeTransfer(data.recipientOnFailure, amountToSend);
                    } else if (!success) {
                        revert SendAndCallFailed();
                    }
                }
            } else if (action.actionType == ActionType.SendAndCallForBeneficiary) {
                SendAndCallForBeneficiary memory data = distribution.sendAndCallForBeneficiary[action.dataIndex];
                uint256 amountToSend = (_amount * data.basisAmount) / 10000;

                if (_paymentToken == address(0)) {
                    bytes memory callData = abi.encodeWithSelector(data.signature, _beneficiary);

                   (bool success, ) = data.recipient.call{value: amountToSend}(callData);

                    if (!success && data.recipientOnFailure != address(0)) {
                        payable(data.recipientOnFailure).sendValue(amountToSend);
                    } else if (!success) {
                        revert SendAndCallForBeneficiaryFailed();
                    }
                } else {
                    IERC20(_paymentToken).approve(data.recipient, amountToSend);
                
                    bytes memory callData = abi.encodeWithSelector(
                        data.signature,
                        _beneficiary,
                        amountToSend
                    );

                   (bool success, ) = data.recipient.call(callData);

                    if (!success && data.recipientOnFailure != address(0)) {
                        IERC20(_paymentToken).safeTransfer(data.recipientOnFailure, amountToSend);
                    } else if (!success) {
                        revert SendAndCallForBeneficiaryFailed();
                    }
                }
            }
        }
    }

    function _swapETHForERC20ExactIn(uint256 ethInAmount, PoolKey memory poolKey) internal returns(uint256 amountOut) {
        uint256 startERC20Amount = IERC20(Currency.unwrap(poolKey.currency1)).balanceOf(address(this));

        console.logUint(startERC20Amount);

        uint128 minAmountOut = 0;
      
        // Encode the Universal Router command
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN_SINGLE),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: true,
                amountIn: uint128(ethInAmount),
                amountOutMinimum: minAmountOut,
                hookData: bytes("")
            })
        );
        params[1] = abi.encode(poolKey.currency0, uint128(ethInAmount));
        params[2] = abi.encode(poolKey.currency1, minAmountOut);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        IUniversalRouter(universalRouter).execute{value: ethInAmount}(commands, inputs, block.timestamp);

        uint256 endERC20Amount = IERC20(Currency.unwrap(poolKey.currency1)).balanceOf(address(this));
   
        console.logUint(endERC20Amount);

        return endERC20Amount;
    }
    
    /// @notice Access control to upgrade the contract. Only the owner can upgrade
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
