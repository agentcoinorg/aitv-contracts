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
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IBurnable} from "./interfaces/IBurnable.sol";
import {UniSwapper} from "./libraries/UniSwapper.sol";

enum ActionType {
    Burn,
    Send,
    Buy,
    SendAndCall,
    SendAndCallForBeneficiary
}

struct RawAction {
    ActionType actionType;
    address token;
    address recipient;
    uint16 basisPoints;
    uint32 distributionId;
    bytes4 selector;
    address recipientOnFailure;
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
    error BasisPointsMustSumTo10000();
    
    event DistributionAdded(uint256 indexed distributionId);

    IPositionManager public uniswapPositionManager;
    IUniversalRouter public uniswapUniversalRouter;
    IPermit2 public permit2;

    mapping(bytes32 => uint256) internal promptDistributionIds;
    mapping(address => PoolKey) internal poolKeys;
    uint256 internal lastDistributionId;
    mapping(uint256 => bytes) internal distributions;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract
    /// @param _owner The owner of the contract and the one who can upgrade it
    /// @param _uniswapPositionManager The address of the position manager
    /// @param _uniswapUniversalRouter The address of the universal router
    function initialize(
        address _owner,
        IPositionManager _uniswapPositionManager,
        IUniversalRouter _uniswapUniversalRouter,
        IPermit2 _permit2
    ) external initializer {
        if (address(_uniswapPositionManager) == address(0) || address(_uniswapUniversalRouter) == address(0)) {
            revert ZeroAddressNotAllowed();
        }

        __Ownable_init(_owner); // Checks for zero address
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        uniswapPositionManager = _uniswapPositionManager;
        uniswapUniversalRouter = _uniswapUniversalRouter;
        permit2 = _permit2;
    }

    function addDistribution(RawAction[] calldata actions)
        external
        onlyOwner
        returns (uint256 distributionId)
    {
        // 1) Sum up all basisPoints; must equal exactly 10 000 (100%)
        uint256 totalBasis;
        for (uint256 i = 0; i < actions.length; ++i) {
            totalBasis += actions[i].basisPoints;
        }
        if (totalBasis != 10_000) revert BasisPointsMustSumTo10000();

        // 2) Assign new ID and store the ABI‐encoded actions blob
        distributionId = ++lastDistributionId;
        distributions[distributionId] = abi.encode(actions);

        // 3) Emit for off‐chain indexing
        emit DistributionAdded(distributionId);
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

    function setPromptDistribution(bytes32 promptType, uint256 distributionId) external virtual onlyOwner returns(uint256) {
        promptDistributionIds[promptType] = distributionId;

        return distributionId;
    }

    function promptWithETH(
        bytes32 _promptType, 
        address _beneficiary
    ) external payable {
        bool isBeneficiaryCall = true;
        uint256 amount = msg.value;

        if (amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        uint256 distributionId = promptDistributionIds[_promptType];

        _execDistribution(distributionId, _beneficiary, amount, address(0), isBeneficiaryCall);
    }

    function promptWithERC20(bytes32 _promptType, address _beneficiary, uint256 _amount, address _paymentToken) external {
        bool isBeneficiaryCall = true;

        if (_amount == 0) {
            revert ZeroAmountNotAllowed();
        }

        IERC20(_paymentToken).safeTransferFrom(msg.sender, address(this), _amount);

        uint256 distributionId = promptDistributionIds[_promptType];

        _execDistribution(distributionId, _beneficiary, _amount, _paymentToken, isBeneficiaryCall);
    }

    function _execDistribution(
        uint256 distributionId,
        address beneficiary,
        uint256 amount,
        address paymentToken,
        bool isBeneficiaryCall
    ) internal {
        if (distributionId == 0) revert DistributionNotFound();

        bytes memory blob = distributions[distributionId];
        RawAction[] memory actions = abi.decode(blob, (RawAction[]));

        for (uint256 i = 0; i < actions.length; ++i) {
            RawAction memory a = actions[i];
            uint256 split = (amount * a.basisPoints) / 10_000;

            console.log("1");
            if (a.actionType == ActionType.Burn) {
                if (paymentToken== address(0)) revert BurningETHNotAllowed();
                IBurnable(paymentToken).burn(split);
            } else if (a.actionType == ActionType.Send) {
                if (paymentToken == address(0)) {
                    payable(a.recipient).sendValue(split);
                } else {
                    console.log("x");
                    IERC20(paymentToken).safeTransfer(a.recipient, split);
                }

            } else if (a.actionType == ActionType.Buy) {
                PoolKey memory pk = poolKeys[a.token];
                uint256 out = UniSwapper.swapExactIn(
                    address(this),
                    pk,
                    paymentToken,
                    a.token,
                    split,
                    1,
                    UniSwapper.Version.V3,
                    uniswapUniversalRouter,
                    permit2
                );

                _execDistribution(a.distributionId, beneficiary, out, a.token, isBeneficiaryCall);

            } else if (
                a.actionType == ActionType.SendAndCall ||
                a.actionType == ActionType.SendAndCallForBeneficiary
            ) {
                address target = a.recipient;
                bool isEth = (paymentToken == address(0));

                bytes memory callData;
                if (a.actionType == ActionType.SendAndCall) {
                    callData = abi.encodeWithSelector(
                        a.selector,
                        isBeneficiaryCall ? beneficiary : msg.sender
                    );
                } else {
                    callData = abi.encodeWithSelector(
                        a.selector,
                        beneficiary
                    );
                }

                if (isEth) {
                    (bool ok, ) = target.call{value: split}(callData);
                    if (!ok) _handleFailureETH(split, a, isBeneficiaryCall);
                } else {
                    IERC20(paymentToken).approve(target, split);
                    (bool ok, ) = target.call(callData);
                    if (!ok) _handleFailureERC20(paymentToken, split, a, isBeneficiaryCall);
                }
            }
        }
    }

    function _handleFailureETH(
        uint256 split,
        RawAction memory a,
        bool isBeneficiaryCall
    ) internal {
        if (isBeneficiaryCall) {
            // Send the ETH back to the beneficiary
            payable(a.recipient).sendValue(split);
        } else {
            // Send the ETH back to the sender
            payable(msg.sender).sendValue(split);
        }
    }

    function _handleFailureERC20(
        address paymentToken,
        uint256 split,
        RawAction memory a,
        bool isBeneficiaryCall
    ) internal {
        if (isBeneficiaryCall) {
            // Send the ERC20 tokens back to the beneficiary
            IERC20(paymentToken).safeTransfer(a.recipient, split);
        } else {
            // Send the ERC20 tokens back to the sender
            IERC20(paymentToken).safeTransfer(msg.sender, split);
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

        uniswapUniversalRouter.execute{value: ethInAmount}(commands, inputs, block.timestamp);

        uint256 endERC20Amount = IERC20(Currency.unwrap(poolKey.currency1)).balanceOf(address(this));

        return endERC20Amount;
    }
    
    /// @notice Access control to upgrade the contract. Only the owner can upgrade
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
