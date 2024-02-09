// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IReferralManager.sol";

import "../libraries/LibMath.sol";
import "../libraries/LibOrderBook.sol";
import "../libraries/LibTypeCast.sol";

import "./Types.sol";
import "./Admin.sol";
import "./Getter.sol";

contract OrderBook is Storage, ReentrancyGuardUpgradeable, Admin, Getter {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for bytes32;
    using LibOrder for OrderData;
    using LibOrder for PositionOrderParams;
    using LibOrder for LiquidityOrderParams;
    using LibOrder for WithdrawalOrderParams;
    using LibOrderBook for OrderBookStorage;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // do not forget to update LibOrderBook if this line updates
    event CancelOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    // do not forget to update LibOrderBook if this line updates
    event NewLiquidityOrder(address indexed account, uint64 indexed orderId, LiquidityOrderParams params);
    // do not forget to update LibOrderBook if this line updates
    event NewPositionOrder(address indexed account, uint64 indexed orderId, PositionOrderParams params);
    // do not forget to update LibOrderBook if this line updates
    event NewWithdrawalOrder(address indexed account, uint64 indexed orderId, WithdrawalOrderParams params);
    // do not forget to update LibOrderBook if this line updates
    event FillOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    // do not forget to update OrderBook if this line updates
    event FillAdlOrder(address indexed account, AdlOrderParams params);
    event ReportLiquidityOrderPrice(
        uint64 indexed orderId,
        uint96[] prices // 1e18
    );

    modifier whenNotPaused(OrderType orderType) {
        require(!_storage.isPaused[orderType], "PAP"); // Paused
        _;
    }

    function initialize(address pool, address mlpToken) external initializer {
        __AccessControlEnumerable_init();

        _storage.pool = pool;
        _storage.mlpToken = mlpToken;

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MAINTAINER_ROLE, _msgSender());
    }

    function placePositionOrder(
        PositionOrderParams memory orderParams,
        bytes32 referralCode
    ) public payable nonReentrant {
        address account = orderParams.subAccountId.owner();
        // otherwise only account owner can place order
        require(account == _msgSender(), "SND"); // SeNDer is not authorized
        address referralManager = _referralManager();
        if (referralCode != bytes32(0) && referralManager != address(0)) {
            IReferralManager(referralManager).setReferrerCodeFor(account, referralCode);
        }
        _storage.placePositionOrder(orderParams, _blockTimestamp());
    }

    function fillAdlOrder(
        AdlOrderParams memory orderParams,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) public onlyRole(BROKER_ROLE) nonReentrant {
        // update funding state
        IDegenPool(_storage.pool).updateFundingState();
        // fill
        _storage.fillAdlOrder(orderParams, tradingPrice, markPrices);
    }

    /**
     * @notice Add/remove liquidity. called by Liquidity Provider.
     *
     *         Can be filled after liquidityLockPeriod seconds.
     * @param  orderParams params of liquidity order.
     *          - assetId:   asset.id that added/removed to.
     *          - rawAmount: asset token amount. decimals = erc20.decimals.
     *          - isAdding:  true for add liquidity, false for remove liquidity.
     */
    function placeLiquidityOrder(LiquidityOrderParams memory orderParams) external payable nonReentrant {
        _storage.placeLiquidityOrder(orderParams, _msgSender(), _blockTimestamp());
    }

    /**
     * @notice Withdraw collateral/profit. called by Trader.
     *
     *         This order will expire after marketOrderTimeout seconds.
     * @param  orderParams       params of withdrawal order.orderParams
     *          - rawAmount:     collateral or profit asset amount. decimals = erc20.decimals.
     *          - profitTokenId: always 0. not supported in DegenPool. only for compatibility
     *          - isProfit:      always false. not supported in DegenPool. only for compatibility
     */
    function placeWithdrawalOrder(WithdrawalOrderParams memory orderParams) external nonReentrant {
        require(orderParams.subAccountId.owner() == _msgSender(), "SND"); // SeNDer is not authorized
        _storage.placeWithdrawalOrder(orderParams, _blockTimestamp());
    }

    /**
     * @dev   Open/close a position. called by Broker.
     *
     * @param orderId           order id.
     * @param filledAmount      fill amount. decimals = 18.
     * @param tradingPrice      trading price. decimals = 18.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillPositionOrder(
        uint64 orderId,
        uint96 filledAmount,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external onlyRole(BROKER_ROLE) whenNotPaused(OrderType.PositionOrder) nonReentrant {
        require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
        OrderData memory orderData = _storage.orderData[orderId];
        _storage.removeOrder(orderData);
        require(orderData.orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch
        PositionOrderParams memory orderParams = orderData.decodePositionOrder();
        require(filledAmount <= orderParams.size, "FAM"); // Fill Amount too Much
        require(_blockTimestamp() <= orderData.placeOrderTime + _positionOrderExpiration(orderParams), "EXP"); // EXPired
        // update funding state
        IDegenPool(_storage.pool).updateFundingState();
        // fill
        if (orderParams.isOpenPosition()) {
            tradingPrice = _storage.fillOpenPositionOrder(
                orderParams,
                orderId,
                filledAmount,
                tradingPrice,
                markPrices,
                _blockTimestamp()
            );
        } else {
            tradingPrice = _storage.fillClosePositionOrder(
                orderParams,
                orderId,
                filledAmount,
                tradingPrice,
                markPrices,
                _blockTimestamp()
            );
        }
        // price check
        // open,long      0,0   0,1   1,1   1,0
        // limitOrder     <=    >=    <=    >=
        // triggerOrder   >=    <=    >=    <=
        bool isLess = (orderParams.subAccountId.isLong() == orderParams.isOpenPosition());
        if (orderParams.isTriggerOrder()) {
            isLess = !isLess;
        }
        if (isLess) {
            require(tradingPrice <= orderParams.price, "LMT"); // LiMiTed by limitPrice
        } else {
            require(tradingPrice >= orderParams.price, "LMT"); // LiMiTed by limitPrice
        }

        emit FillOrder(orderData.account, orderId, orderData);
    }

    /**
     * @dev   Add/remove liquidity. called by Broker.
     *
     *        Check _getLiquidityFeeRate in Liquidity.sol on how to calculate liquidity fee.
     * @param orderId           order id.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillLiquidityOrder(
        uint64 orderId,
        uint96[] calldata markPrices
    ) external onlyRole(BROKER_ROLE) whenNotPaused(OrderType.LiquidityOrder) nonReentrant {
        emit ReportLiquidityOrderPrice(orderId, markPrices);
        require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
        OrderData memory orderData = _storage.orderData[orderId];
        _storage.removeOrder(orderData);
        bool hasCallback = hasRole(CALLBACKER_ROLE, orderData.account);
        if (hasCallback) {
            // we can add callback in the future
        }
        require(orderData.orderType == OrderType.LiquidityOrder, "TYP"); // order TYPe mismatch
        // update funding state
        IDegenPool(_storage.pool).updateFundingState();
        // fill
        _storage.fillLiquidityOrder(orderData, markPrices, _blockTimestamp());
        if (hasCallback) {
            // we can add callback in the future
        }
        emit FillOrder(orderData.account, orderId, orderData);
    }

    function donateLiquidity(
        uint8 assetId,
        uint96 rawAmount // erc20.decimals
    ) external {
        _storage.donateLiquidity(_msgSender(), assetId, rawAmount);
    }

    /**
     * @dev   Withdraw collateral/profit. called by Broker.
     *
     * @param orderId           order id.
     * @param markPrices        mark prices of all assets. decimals = 18.
     */
    function fillWithdrawalOrder(
        uint64 orderId,
        uint96[] memory markPrices
    ) external onlyRole(BROKER_ROLE) whenNotPaused(OrderType.WithdrawalOrder) nonReentrant {
        require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
        OrderData memory orderData = _storage.orderData[orderId];
        _storage.removeOrder(orderData);

        require(orderData.orderType == OrderType.WithdrawalOrder, "TYP"); // order TYPe mismatch
        WithdrawalOrderParams memory orderParams = orderData.decodeWithdrawalOrder();
        require(_blockTimestamp() <= orderData.placeOrderTime + _marketOrderTimeout(), "EXP"); // EXPired
        // update funding state
        IDegenPool(_storage.pool).updateFundingState();
        // fill
        if (orderParams.isProfit) {
            require(false, "PFT"); // withdraw profit is not supported yet
        } else {
            uint96 collateralPrice = markPrices[orderParams.subAccountId.collateralId()];
            uint96 assetPrice = markPrices[orderParams.subAccountId.assetId()];
            IDegenPool(_storage.pool).withdrawCollateral(
                orderParams.subAccountId,
                orderParams.rawAmount,
                collateralPrice,
                assetPrice
            );
        }
        emit FillOrder(orderData.account, orderId, orderData);
    }

    /**
     * @notice Cancel an Order by orderId.
     */
    function cancelOrder(uint64 orderId) external nonReentrant {
        require(_storage.orders.contains(orderId), "OID"); // can not find this OrderID
        OrderData memory orderData = _storage.orderData[orderId];
        _storage.removeOrder(orderData);

        uint256 coolDown = _cancelCoolDown();
        require(_blockTimestamp() >= orderData.placeOrderTime + coolDown, "CLD"); // CooLDown
        address account = orderData.account;
        if (orderData.orderType == OrderType.PositionOrder) {
            PositionOrderParams memory orderParams = orderData.decodePositionOrder();
            if (hasRole(BROKER_ROLE, _msgSender())) {
                require(_blockTimestamp() > orderData.placeOrderTime + _positionOrderExpiration(orderParams), "EXP"); // EXPired
            } else {
                require(_msgSender() == account, "SND"); // SeNDer is not authorized
            }
            if (orderParams.isOpenPosition() && orderParams.collateral > 0) {
                uint8 collateralId = orderParams.subAccountId.collateralId();
                address collateralAddress = IDegenPool(_storage.pool)
                    .getAssetParameter(collateralId, LibConfigKeys.TOKEN_ADDRESS)
                    .toAddress();
                LibOrderBook._transferOut(collateralAddress, account, orderParams.collateral);
            }
            // tp/sl strategy
            _storage.tpslOrders[orderParams.subAccountId].remove(uint256(orderId));
        } else if (orderData.orderType == OrderType.LiquidityOrder) {
            require(_msgSender() == account, "SND"); // SeNDer is not authorized
            LiquidityOrderParams memory orderParams = orderData.decodeLiquidityOrder();
            _cancelLiquidityOrder(orderParams, account);
        } else if (orderData.orderType == OrderType.WithdrawalOrder) {
            if (hasRole(BROKER_ROLE, _msgSender())) {
                uint256 deadline = orderData.placeOrderTime + _marketOrderTimeout();
                require(_blockTimestamp() > deadline, "EXP"); // not EXPired yet
            } else {
                require(_msgSender() == account, "SND"); // SeNDer is not authorized
            }
        } else {
            revert();
        }
        emit CancelOrder(orderData.account, orderId, orderData);
    }

    function _cancelLiquidityOrder(LiquidityOrderParams memory orderParams, address account) internal {
        if (orderParams.isAdding) {
            address collateralAddress = IDegenPool(_storage.pool)
                .getAssetParameter(orderParams.assetId, LibConfigKeys.TOKEN_ADDRESS)
                .toAddress();
            LibOrderBook._transferOut(collateralAddress, account, orderParams.rawAmount);
        } else {
            IERC20Upgradeable(_storage.mlpToken).safeTransfer(account, orderParams.rawAmount);
        }
        // if (_storage.callbackWhitelist[orderParams.account]) {
        //     try
        //         ILiquidityCallback(orderParams.account).afterCancelLiquidityOrder{ gas: _callbackGasLimit() }(order)
        //     {} catch {}
        // }
    }

    /**
     * @notice Trader can withdraw all collateral only when position = 0.
     */
    function withdrawAllCollateral(bytes32 subAccountId) external {
        require(subAccountId.owner() == _msgSender(), "SND"); // SeNDer is not authorized
        IDegenPool(_storage.pool).withdrawAllCollateral(subAccountId);
    }

    /**
     * @notice Anyone can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _updateFundingState in Liquidity.sol and _getBorrowing in Trade.sol
     *         on how to calculate funding and borrowing.
     */
    function updateFundingState() external {
        IDegenPool(_storage.pool).updateFundingState();
    }

    /**
     * @notice Deposit collateral into a subAccount.
     *
     * @param  subAccountId       sub account id. see LibSubAccount.decodeSubAccountId.
     * @param  collateralAmount   collateral amount. decimals = erc20.decimals.
     */
    function depositCollateral(bytes32 subAccountId, uint256 collateralAmount) external payable {
        require(subAccountId.owner() == _msgSender(), "SND"); // SeNDer is not authorized
        require(collateralAmount != 0, "C=0"); // Collateral Is Zero
        address collateralAddress = IDegenPool(_storage.pool)
            .getAssetParameter(subAccountId.collateralId(), LibConfigKeys.TOKEN_ADDRESS)
            .toAddress();
        LibOrderBook._transferIn(_msgSender(), collateralAddress, address(_storage.pool), collateralAmount);
        IDegenPool(_storage.pool).depositCollateral(subAccountId, collateralAmount);
    }

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 tradingPrice,
        uint96[] memory assetPrices
    ) external onlyRole(BROKER_ROLE) {
        // update funding state
        IDegenPool(_storage.pool).updateFundingState();
        // fill
        IDegenPool(_storage.pool).liquidate(subAccountId, profitAssetId, tradingPrice, assetPrices);
        // auto withdraw
        (uint96 collateral, , , , ) = IDegenPool(_storage.pool).getSubAccount(subAccountId);
        if (collateral > 0) {
            IDegenPool(_storage.pool).withdrawAllCollateral(subAccountId);
        }
        // cancel activated tp/sl orders
        _storage.cancelActivatedTpslOrders(subAccountId);
    }

    /**
     * @dev Broker can withdraw brokerGasRebate.
     */
    function claimBrokerGasRebate(uint8 assetId) external onlyRole(BROKER_ROLE) returns (uint256 rawAmount) {
        return IDegenPool(_storage.pool).claimBrokerGasRebate(_msgSender(), assetId);
    }

    function _gasAmount() internal view returns (uint256) {
        uint256 limit = _callbackGasLimit();
        return limit == 0 ? gasleft() : limit;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    function _positionOrderExpiration(PositionOrderParams memory orderParams) internal view returns (uint32) {
        return orderParams.isMarketOrder() ? _marketOrderTimeout() : _maxLimitOrderTimeout();
    }
}
