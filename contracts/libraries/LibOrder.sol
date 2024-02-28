// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./LibSubAccount.sol";
import "../orderbook/Types.sol";

library LibOrder {
    using LibSubAccount for bytes32;
    // position order flags
    uint8 constant POSITION_OPEN = 0x80; // this flag means openPosition; otherwise closePosition
    uint8 constant POSITION_MARKET_ORDER = 0x40; // this flag only affects order expire time and show a better effect on UI
    uint8 constant POSITION_WITHDRAW_ALL_IF_EMPTY = 0x20; // this flag means auto withdraw all collateral if position.size == 0
    uint8 constant POSITION_TRIGGER_ORDER = 0x10; // this flag means this is a trigger order (ex: stop-loss order). otherwise this is a limit order (ex: take-profit order)
    uint8 constant POSITION_TPSL_STRATEGY = 0x08; // for open-position-order, this flag auto place take-profit and stop-loss orders when open-position-order fills.
    //                                               for close-position-order, this flag means ignore limitPrice and profitTokenId, and use extra.tpPrice, extra.slPrice, extra.tpslProfitTokenId instead.
    uint8 constant POSITION_SHOULD_REACH_MIN_PROFIT = 0x04; // this flag is used to ensure that either the minProfitTime is met or the minProfitRate ratio is reached when close a position. only available when minProfitTime > 0.
    uint8 constant POSITION_AUTO_DELEVERAGE = 0x02; // denotes that this order is an auto-deleverage order
    // order data[1] SHOULD reserve lower 64bits for enumIndex
    bytes32 constant ENUM_INDEX_BITS = bytes32(uint256(0xffffffffffffffff));

    // check Types.PositionOrder for schema
    function encodePositionOrder(
        PositionOrderParams memory orderParams,
        uint64 orderId,
        uint32 blockTimestamp
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.PositionOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.account = orderParams.subAccountId.owner();
        orderData.placeOrderTime = blockTimestamp;
        orderData.payload = abi.encode(orderParams);
    }

    // check Types.PositionOrder for schema
    function decodePositionOrder(
        OrderData memory orderData
    ) internal pure returns (PositionOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.PositionOrder, "ODT"); // OrDer Type
        require(orderData.version == 1, "ODV"); // OrDer Version
        require(orderData.payload.length == 11 * 32, "ODP"); // OrDer Payload
        orderParams = abi.decode(orderData.payload, (PositionOrderParams));
    }

    // check Types.LiquidityOrder for schema
    function encodeLiquidityOrder(
        LiquidityOrderParams memory orderParams,
        uint64 orderId,
        address account,
        uint32 blockTimestamp
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.LiquidityOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.account = account;
        orderData.placeOrderTime = blockTimestamp;
        orderData.payload = abi.encode(orderParams);
    }

    // check Types.LiquidityOrder for schema
    function decodeLiquidityOrder(
        OrderData memory orderData
    ) internal pure returns (LiquidityOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.LiquidityOrder, "ODT"); // OrDer Type
        require(orderData.version == 1, "ODV"); // OrDer Version
        require(orderData.payload.length == 3 * 32, "ODP"); // OrDer Payload
        orderParams = abi.decode(orderData.payload, (LiquidityOrderParams));
    }

    // check Types.WithdrawalOrder for schema
    function encodeWithdrawalOrder(
        WithdrawalOrderParams memory orderParams,
        uint64 orderId,
        uint32 blockTimestamp
    ) internal pure returns (OrderData memory orderData) {
        orderData.orderType = OrderType.WithdrawalOrder;
        orderData.id = orderId;
        orderData.version = 1;
        orderData.account = orderParams.subAccountId.owner();
        orderData.placeOrderTime = blockTimestamp;
        orderData.payload = abi.encode(orderParams);
    }

    // check Types.WithdrawalOrder for schema
    function decodeWithdrawalOrder(
        OrderData memory orderData
    ) internal pure returns (WithdrawalOrderParams memory orderParams) {
        require(orderData.orderType == OrderType.WithdrawalOrder, "ODT"); // OrDer Type
        require(orderData.version == 1, "ODV"); // OrDer Version
        require(orderData.payload.length == 4 * 32, "ODP"); // OrDer Payload
        orderParams = abi.decode(orderData.payload, (WithdrawalOrderParams));
    }

    function isOpenPosition(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_OPEN) != 0;
    }

    function isMarketOrder(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_MARKET_ORDER) != 0;
    }

    function isWithdrawIfEmpty(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_WITHDRAW_ALL_IF_EMPTY) != 0;
    }

    function isTriggerOrder(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_TRIGGER_ORDER) != 0;
    }

    function isTpslStrategy(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_TPSL_STRATEGY) != 0;
    }

    function shouldReachMinProfit(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_SHOULD_REACH_MIN_PROFIT) != 0;
    }

    function isAdl(PositionOrderParams memory orderParams) internal pure returns (bool) {
        return (orderParams.flags & POSITION_AUTO_DELEVERAGE) != 0;
    }
}
