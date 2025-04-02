// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "../interfaces/IDegenPool.sol";
import "../libraries/LibOrder.sol";

enum OrderType {
    None, // 0
    PositionOrder, // 1
    LiquidityOrder, // 2
    WithdrawalOrder // 3
}

bytes32 constant BROKER_ROLE = keccak256("BROKER_ROLE");
bytes32 constant CALLBACKER_ROLE = keccak256("CALLBACKER_ROLE");
bytes32 constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

struct OrderData {
    address account;
    uint64 id;
    OrderType orderType;
    uint8 version;
    uint32 placeOrderTime;
    bytes payload;
}

struct OrderBookStorage {
    address mlpToken;
    address pool;
    uint64 nextOrderId;
    mapping(OrderType => bool) isPaused;
    mapping(bytes32 => bytes32) parameters;
    // orders
    bytes32 _reserved1;
    bytes32 _reserved2;
    bytes32 _reserved3;
    bytes32 _reserved4;
    mapping(uint64 => OrderData) orderData;
    EnumerableSetUpgradeable.UintSet orders;
    mapping(bytes32 => EnumerableSetUpgradeable.UintSet) tpslOrders;
    mapping(address => EnumerableSetUpgradeable.UintSet) userOrders;
    mapping(address => bool) delegators;
}

struct PositionOrderParams {
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 collateral; // erc20.decimals
    uint96 size; // 1e18
    uint96 price; // 1e18
    uint96 tpPrice; // take-profit price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
    uint96 slPrice; // stop-loss price. decimals = 18. only valid when flags.POSITION_TPSL_STRATEGY.
    uint32 expiration; // 1e0 seconds
    uint32 tpslExpiration; // 1e0 seconds
    uint8 profitTokenId;
    uint8 tpslProfitTokenId; // only valid when flags.POSITION_TPSL_STRATEGY.
    uint8 flags;
}

struct LiquidityOrderParams {
    uint96 rawAmount; // erc20.decimals
    uint8 assetId;
    bool isAdding;
}

struct WithdrawalOrderParams {
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 rawAmount; // erc20.decimals
    uint8 profitTokenId; // always 0. not supported in DegenPool. only for compatibility
    bool isProfit; // always false. not supported in DegenPool. only for compatibility
}

struct AdlOrderParams {
    bytes32 subAccountId; // 160 + 8 + 8 + 8 = 184
    uint96 size; // 1e18
    uint96 price; // 1e18
    uint8 profitTokenId;
}
