// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../interfaces/IReferralManager.sol";
import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../orderbook/Types.sol";
import "../orderbook/Storage.sol";

library LibOrderBook {
    using LibSubAccount for bytes32;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for bytes32;
    using LibTypeCast for uint256;
    using LibOrder for PositionOrderParams;
    using LibOrder for LiquidityOrderParams;
    using LibOrder for WithdrawalOrderParams;
    using LibOrder for OrderData;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using LibMath for uint256;

    // do not forget to update OrderBook if this line updates
    event CancelOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    // do not forget to update OrderBook if this line updates
    event NewLiquidityOrder(address indexed account, uint64 indexed orderId, LiquidityOrderParams params);
    // do not forget to update OrderBook if this line updates
    event NewPositionOrder(address indexed account, uint64 indexed orderId, PositionOrderParams params);
    // do not forget to update OrderBook if this line updates
    event NewWithdrawalOrder(address indexed account, uint64 indexed orderId, WithdrawalOrderParams params);
    // do not forget to update OrderBook if this line updates
    event FillOrder(address indexed account, uint64 indexed orderId, OrderData orderData);
    // do not forget to update OrderBook if this line updates
    event FillAdlOrder(address indexed account, AdlOrderParams params);

    uint256 public constant MAX_TP_SL_ORDERS = 32;

    function liquidityLockPeriod(OrderBookStorage storage orderBook) internal view returns (uint32) {
        return orderBook.parameters[LibConfigKeys.OB_LIQUIDITY_LOCK_PERIOD].toUint32();
    }

    function appendOrder(OrderBookStorage storage orderBook, OrderData memory orderData) internal {
        orderBook.orderData[orderData.id] = orderData;
        orderBook.orders.add(orderData.id);
        orderBook.userOrders[orderData.account].add(orderData.id);
    }

    function removeOrder(OrderBookStorage storage orderBook, OrderData memory orderData) internal {
        orderBook.userOrders[orderData.account].remove(orderData.id);
        orderBook.orders.remove(orderData.id);
        delete orderBook.orderData[orderData.id];
    }

    function placeLiquidityOrder(
        OrderBookStorage storage orderBook,
        LiquidityOrderParams memory orderParams,
        address account,
        uint32 blockTimestamp
    ) external {
        require(orderParams.rawAmount != 0, "A=0"); // Amount Is Zero
        _validateAssets(
            orderBook,
            orderParams.assetId,
            ASSET_IS_ENABLED | ASSET_CAN_ADD_REMOVE_LIQUIDITY | ASSET_IS_STABLE,
            0
        );
        if (orderParams.isAdding) {
            address collateralAddress = IDegenPool(orderBook.pool)
                .getAssetParameter(orderParams.assetId, LibConfigKeys.TOKEN_ADDRESS)
                .toAddress();
            _transferIn(account, collateralAddress, address(this), orderParams.rawAmount);
        } else {
            IERC20Upgradeable(orderBook.mlpToken).safeTransferFrom(account, address(this), orderParams.rawAmount);
        }
        uint64 orderId = orderBook.nextOrderId++;
        OrderData memory orderData = orderParams.encodeLiquidityOrder(orderId, account, blockTimestamp);
        appendOrder(orderBook, orderData);
        emit NewLiquidityOrder(account, orderId, orderParams);
    }

    function fillLiquidityOrder(
        OrderBookStorage storage orderBook,
        OrderData memory orderData,
        uint96[] memory markPrices,
        uint32 blockTimestamp
    ) external returns (uint256 outAmount) {
        LiquidityOrderParams memory orderParams = orderData.decodeLiquidityOrder();
        require(blockTimestamp >= orderData.placeOrderTime + liquidityLockPeriod(orderBook), "LCK"); // mlp token is LoCKed
        uint96 rawAmount = orderParams.rawAmount;
        if (orderParams.isAdding) {
            IERC20Upgradeable collateral = IERC20Upgradeable(
                IDegenPool(orderBook.pool)
                    .getAssetParameter(orderParams.assetId, LibConfigKeys.TOKEN_ADDRESS)
                    .toAddress()
            );
            collateral.safeTransfer(orderBook.pool, rawAmount);
            outAmount = IDegenPool(orderBook.pool).addLiquidity(
                orderData.account,
                orderParams.assetId,
                rawAmount,
                markPrices
            );
        } else {
            outAmount = IDegenPool(orderBook.pool).removeLiquidity(
                orderData.account,
                rawAmount,
                orderParams.assetId,
                markPrices
            );
        }
    }

    function donateLiquidity(
        OrderBookStorage storage orderBook,
        address account,
        uint8 assetId,
        uint96 rawAmount // erc20.decimals
    ) external {
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        address collateralAddress = IDegenPool(orderBook.pool)
            .getAssetParameter(assetId, LibConfigKeys.TOKEN_ADDRESS)
            .toAddress();
        _transferIn(account, collateralAddress, address(orderBook.pool), rawAmount);
        IDegenPool(orderBook.pool).donateLiquidity(account, assetId, rawAmount);
    }

    function placePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint32 blockTimestamp
    ) external {
        require(orderParams.size != 0, "S=0"); // order Size Is Zero
        require(orderParams.expiration > blockTimestamp, "D<0"); // Deadline is earlier than now
        require(orderParams.price > 0, "P=0"); // must have Price
        if (orderParams.profitTokenId > 0) {
            // note: profitTokenId == 0 is also valid, this only partially protects the function from misuse
            require(!orderParams.isOpenPosition(), "T!0"); // opening position does not need a profit Token id
        }
        // verify asset
        _validateAssets(
            orderBook,
            orderParams.subAccountId.assetId(),
            ASSET_IS_TRADABLE | ASSET_IS_ENABLED,
            ASSET_IS_STABLE
        );
        _validateAssets(orderBook, orderParams.subAccountId.collateralId(), ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
        {
            uint96 lotSize = IDegenPool(orderBook.pool)
                .getAssetParameter(orderParams.subAccountId.assetId(), LibConfigKeys.LOT_SIZE)
                .toUint96();
            require(orderParams.size % lotSize == 0, "LOT"); // LOT size mismatch
        }
        require(!orderParams.isAdl(), "ADL"); // Auto DeLeverage is not allowed
        if (orderParams.isOpenPosition()) {
            _placeOpenPositionOrder(orderBook, orderParams, blockTimestamp);
        } else {
            _placeClosePositionOrder(orderBook, orderParams, blockTimestamp);
        }
    }

    function _placeOpenPositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint32 blockTimestamp
    ) private {
        // fetch collateral
        if (orderParams.collateral > 0) {
            address accountOwner = orderParams.subAccountId.owner();
            uint8 collateralId = orderParams.subAccountId.collateralId();
            address collateralAddress = IDegenPool(orderBook.pool)
                .getAssetParameter(collateralId, LibConfigKeys.TOKEN_ADDRESS)
                .toAddress();
            _transferIn(accountOwner, collateralAddress, address(this), orderParams.collateral);
        }
        if (orderParams.isTpslStrategy()) {
            // tp/sl strategy
            require((orderParams.tpPrice > 0 || orderParams.slPrice > 0), "TPSL"); // TP/SL strategy need tpPrice and/or slPrice
            require(orderParams.tpslExpiration > blockTimestamp, "D<0"); // Deadline is earlier than now
        }
        // add order
        _placePositionOrder(orderBook, orderParams, blockTimestamp);
    }

    function _placeClosePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint32 blockTimestamp
    ) private {
        if (orderParams.isTpslStrategy()) {
            // tp/sl strategy
            require(orderParams.collateral == 0, "C!0"); // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
            require(orderParams.profitTokenId == 0, "T!0"); // use extra.tpProfitTokenId instead
            require(!orderParams.isMarketOrder(), "MKT"); // tp/sl strategy does not support MarKeT order
            require(orderParams.tpPrice > 0 && orderParams.slPrice > 0, "TPSL"); // tp/sl strategy need tpPrice and slPrice. otherwise use POSITION_TRIGGER_ORDER instead
            require(orderParams.tpslExpiration > blockTimestamp, "D<0"); // Deadline is earlier than now
            _validateAssets(orderBook, orderParams.tpslProfitTokenId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
            _placeTpslOrders(orderBook, orderParams, blockTimestamp);
        } else {
            // normal close-position-order
            _validateAssets(orderBook, orderParams.profitTokenId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
            if (orderParams.shouldReachMinProfit()) {
                // POSITION_MUST_PROFIT is only available if asset.minProfitTime > 0
                uint8 assetId = orderParams.subAccountId.assetId();
                uint32 minProfitTime = IDegenPool(orderBook.pool)
                    .getAssetParameter(assetId, LibConfigKeys.MIN_PROFIT_TIME)
                    .toUint32();
                require(minProfitTime > 0, "MPT"); // asset MinProfitTime is 0
            }
            _validateAssets(orderBook, orderParams.profitTokenId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
            _placePositionOrder(orderBook, orderParams, blockTimestamp);
        }
    }

    function cancelActivatedTpslOrders(OrderBookStorage storage orderBook, bytes32 subAccountId) public {
        EnumerableSetUpgradeable.UintSet storage orderIds = orderBook.tpslOrders[subAccountId];
        uint256 length = orderIds.length();
        for (uint256 i = 0; i < length; i++) {
            uint64 orderId = uint64(orderIds.at(i));
            require(orderBook.orders.contains(orderId), "OID"); // can not find this OrderID

            OrderData memory orderData = orderBook.orderData[orderId];
            OrderType orderType = OrderType(orderData.orderType);
            require(orderType == OrderType.PositionOrder, "TYP"); // order TYPe mismatch
            PositionOrderParams memory orderParams = orderData.decodePositionOrder();
            require(!orderParams.isOpenPosition() && orderParams.collateral == 0, "CLS"); // should be CLoSe position order and no withdraw
            removeOrder(orderBook, orderData);

            emit CancelOrder(orderData.account, orderId, orderData);
        }
        delete orderBook.tpslOrders[subAccountId]; // tp/sl strategy
    }

    function placeWithdrawalOrder(
        OrderBookStorage storage orderBook,
        WithdrawalOrderParams memory orderParams,
        uint32 blockTimestamp
    ) external {
        require(orderParams.rawAmount != 0, "A=0"); // Amount Is Zero
        uint64 newOrderId = orderBook.nextOrderId++;
        OrderData memory orderData = orderParams.encodeWithdrawalOrder(newOrderId, blockTimestamp);
        appendOrder(orderBook, orderData);
        emit NewWithdrawalOrder(orderData.account, newOrderId, orderParams);
    }

    function fillOpenPositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint64 orderId,
        uint96 fillAmount,
        uint96 tradingPrice,
        uint96[] memory markPrices,
        uint32 blockTimestamp
    ) external returns (uint96 retTradingPrice) {
        // auto deposit
        if (orderParams.collateral > 0) {
            uint8 collateralId = orderParams.subAccountId.collateralId();
            address collateralAddress = IDegenPool(orderBook.pool)
                .getAssetParameter(collateralId, LibConfigKeys.TOKEN_ADDRESS)
                .toAddress();
            IERC20Upgradeable(collateralAddress).safeTransfer(address(orderBook.pool), orderParams.collateral);
            IDegenPool(orderBook.pool).depositCollateral(orderParams.subAccountId, orderParams.collateral);
        }
        // open
        tradingPrice = IDegenPool(orderBook.pool).openPosition(
            orderParams.subAccountId,
            fillAmount,
            tradingPrice,
            markPrices
        );
        // tp/sl strategy
        if (orderParams.isTpslStrategy()) {
            _placeTpslOrders(orderBook, orderParams, blockTimestamp);
        }
        return tradingPrice;
    }

    function fillClosePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint64 orderId,
        uint96 fillAmount,
        uint96 tradingPrice,
        uint96[] memory markPrices,
        uint32 blockTimestamp
    ) external returns (uint96 retTradingPrice) {
        // check min profit
        SubAccount memory oldSubAccount;
        if (orderParams.shouldReachMinProfit()) {
            (
                oldSubAccount.collateral,
                oldSubAccount.size,
                oldSubAccount.lastIncreasedTime,
                oldSubAccount.entryPrice,
                oldSubAccount.entryFunding
            ) = IDegenPool(orderBook.pool).getSubAccount(orderParams.subAccountId);
        }
        // close
        tradingPrice = IDegenPool(orderBook.pool).closePosition(
            orderParams.subAccountId,
            fillAmount,
            tradingPrice,
            orderParams.profitTokenId,
            markPrices
        );
        // check min profit
        if (orderParams.shouldReachMinProfit()) {
            require(_hasPassMinProfit(orderBook, orderParams, oldSubAccount, blockTimestamp, tradingPrice), "PFT"); // order must have ProFiT
        }
        // auto withdraw
        uint96 collateralAmount = orderParams.collateral;
        if (collateralAmount > 0) {
            uint96 collateralPrice = markPrices[orderParams.subAccountId.collateralId()];
            uint96 assetPrice = markPrices[orderParams.subAccountId.assetId()];
            IDegenPool(orderBook.pool).withdrawCollateral(
                orderParams.subAccountId,
                collateralAmount,
                collateralPrice,
                assetPrice
            );
        }
        // tp/sl strategy
        orderBook.tpslOrders[orderParams.subAccountId].remove(uint256(orderId));
        // is the position completely closed
        (uint96 collateral, uint96 size, , , ) = IDegenPool(orderBook.pool).getSubAccount(orderParams.subAccountId);
        if (size == 0) {
            // auto withdraw
            if (orderParams.isWithdrawIfEmpty() && collateral > 0) {
                IDegenPool(orderBook.pool).withdrawAllCollateral(orderParams.subAccountId);
            }

            // cancel activated tp/sl orders
            cancelActivatedTpslOrders(orderBook, orderParams.subAccountId);
        }
        return tradingPrice;
    }

    function fillAdlOrder(
        OrderBookStorage storage orderBook,
        AdlOrderParams memory orderParams,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external returns (uint96 retTradingPrice) {
        // pre-check
        {
            uint96 markPrice = markPrices[orderParams.subAccountId.assetId()];
            require(IDegenPool(orderBook.pool).isDeleverageAllowed(orderParams.subAccountId, markPrice), "DLA"); // DeLeverage is not Allowed
        }
        // fill
        {
            uint96 fillAmount = orderParams.size;
            tradingPrice = IDegenPool(orderBook.pool).closePosition(
                orderParams.subAccountId,
                fillAmount,
                tradingPrice,
                orderParams.profitTokenId,
                markPrices
            );
        }
        // price check
        {
            bool isLess = !orderParams.subAccountId.isLong();
            if (isLess) {
                require(tradingPrice <= orderParams.price, "LMT"); // LiMiTed by limitPrice
            } else {
                require(tradingPrice >= orderParams.price, "LMT"); // LiMiTed by limitPrice
            }
        }
        // is the position completely closed
        (uint96 collateral, uint96 size, , , ) = IDegenPool(orderBook.pool).getSubAccount(orderParams.subAccountId);
        if (size == 0) {
            // auto withdraw
            if (collateral > 0) {
                IDegenPool(orderBook.pool).withdrawAllCollateral(orderParams.subAccountId);
            }
            // cancel activated tp/sl orders
            cancelActivatedTpslOrders(orderBook, orderParams.subAccountId);
        }
        emit FillAdlOrder(orderParams.subAccountId.owner(), orderParams);
        return tradingPrice;
    }

    function _placeTpslOrders(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        uint32 blockTimestamp
    ) private {
        if (orderParams.tpPrice > 0 || orderParams.slPrice > 0) {
            _validateAssets(orderBook, orderParams.tpslProfitTokenId, ASSET_IS_STABLE | ASSET_IS_ENABLED, 0);
        }
        if (orderParams.tpPrice > 0) {
            uint8 flags = LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY;
            uint8 assetId = orderParams.subAccountId.assetId();
            uint32 minProfitTime = IDegenPool(orderBook.pool)
                .getAssetParameter(assetId, LibConfigKeys.MIN_PROFIT_TIME)
                .toUint32();
            if (minProfitTime > 0) {
                flags |= LibOrder.POSITION_SHOULD_REACH_MIN_PROFIT;
            }
            uint64 orderId = _placePositionOrder(
                orderBook,
                PositionOrderParams({
                    subAccountId: orderParams.subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: orderParams.size,
                    price: orderParams.tpPrice,
                    tpPrice: 0,
                    slPrice: 0,
                    expiration: orderParams.tpslExpiration,
                    tpslExpiration: 0,
                    profitTokenId: orderParams.tpslProfitTokenId,
                    tpslProfitTokenId: 0,
                    flags: flags
                }),
                blockTimestamp
            );
            orderBook.tpslOrders[orderParams.subAccountId].add(uint256(orderId));
            require(orderBook.tpslOrders[orderParams.subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
        if (orderParams.slPrice > 0) {
            uint64 orderId = _placePositionOrder(
                orderBook,
                PositionOrderParams({
                    subAccountId: orderParams.subAccountId,
                    collateral: 0, // tp/sl strategy only supports POSITION_WITHDRAW_ALL_IF_EMPTY
                    size: orderParams.size,
                    price: orderParams.slPrice,
                    tpPrice: 0,
                    slPrice: 0,
                    expiration: orderParams.tpslExpiration,
                    tpslExpiration: 0,
                    profitTokenId: orderParams.tpslProfitTokenId,
                    tpslProfitTokenId: 0,
                    flags: LibOrder.POSITION_WITHDRAW_ALL_IF_EMPTY | LibOrder.POSITION_TRIGGER_ORDER
                }),
                blockTimestamp
            );
            orderBook.tpslOrders[orderParams.subAccountId].add(uint256(orderId));
            require(orderBook.tpslOrders[orderParams.subAccountId].length() <= MAX_TP_SL_ORDERS, "TMO"); // Too Many TP/SL Orders
        }
    }

    function _placePositionOrder(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams, // NOTE: id, placeOrderTime, expire10s will be ignored
        uint32 blockTimestamp
    ) private returns (uint64 newOrderId) {
        newOrderId = orderBook.nextOrderId++;
        OrderData memory orderData = orderParams.encodePositionOrder(newOrderId, blockTimestamp);
        appendOrder(orderBook, orderData);
        emit NewPositionOrder(orderParams.subAccountId.owner(), newOrderId, orderParams);
    }

    function _hasPassMinProfit(
        OrderBookStorage storage orderBook,
        PositionOrderParams memory orderParams,
        SubAccount memory oldSubAccount,
        uint32 blockTimestamp,
        uint96 tradingPrice
    ) private view returns (bool) {
        if (oldSubAccount.size == 0) {
            return true;
        }
        require(tradingPrice > 0, "P=0"); // Price Is Zero
        bool hasProfit = orderParams.subAccountId.isLong()
            ? tradingPrice > oldSubAccount.entryPrice
            : tradingPrice < oldSubAccount.entryPrice;
        if (!hasProfit) {
            return true;
        }
        uint8 assetId = orderParams.subAccountId.assetId();
        uint32 minProfitTime = IDegenPool(orderBook.pool)
            .getAssetParameter(assetId, LibConfigKeys.MIN_PROFIT_TIME)
            .toUint32();
        uint32 minProfitRate = IDegenPool(orderBook.pool)
            .getAssetParameter(assetId, LibConfigKeys.MIN_PROFIT_RATE)
            .toUint32();
        if (blockTimestamp >= oldSubAccount.lastIncreasedTime + minProfitTime) {
            return true;
        }
        uint96 priceDelta = tradingPrice >= oldSubAccount.entryPrice
            ? tradingPrice - oldSubAccount.entryPrice
            : oldSubAccount.entryPrice - tradingPrice;
        if (priceDelta >= uint256(oldSubAccount.entryPrice).rmul(minProfitRate).toUint96()) {
            return true;
        }
        return false;
    }

    function _transferIn(
        // OrderBookStorage storage orderBook,
        address trader,
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        // commented: if tokenAddress == orderBook.wethToken
        require(msg.value == 0, "VAL"); // transaction VALue SHOULD be 0
        IERC20Upgradeable(tokenAddress).safeTransferFrom(trader, recipient, rawAmount);
    }

    function _transferOut(
        // OrderBookStorage storage orderBook,
        address tokenAddress,
        address recipient,
        uint256 rawAmount
    ) internal {
        // commented: if tokenAddress == orderBook.wethToken
        IERC20Upgradeable(tokenAddress).safeTransfer(recipient, rawAmount);
    }

    function _validateAssets(
        OrderBookStorage storage orderBook,
        uint8 assetId,
        uint56 includes,
        uint56 excludes
    ) internal view {
        uint56 flags = IDegenPool(orderBook.pool).getAssetFlags(assetId);
        require((flags & includes == includes) && (flags & excludes == 0), "FLG");
    }
}
