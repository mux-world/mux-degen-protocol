// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

library LibConfigKeys {
    // POOL
    bytes32 constant MLP_TOKEN = keccak256("MLP_TOKEN");
    bytes32 constant ORDER_BOOK = keccak256("ORDER_BOOK");
    bytes32 constant FEE_DISTRIBUTOR = keccak256("FEE_DISTRIBUTOR");

    bytes32 constant FUNDING_INTERVAL = keccak256("FUNDING_INTERVAL"); // 1e0
    bytes32 constant BORROWING_RATE_APY = keccak256("BORROWING_RATE_APY"); // 1e5

    bytes32 constant LIQUIDITY_FEE_RATE = keccak256("LIQUIDITY_FEE_RATE"); // 1e5

    bytes32 constant STRICT_STABLE_DEVIATION = keccak256("STRICT_STABLE_DEVIATION"); // 1e5
    bytes32 constant BROKER_GAS_REBATE_USD = keccak256("BROKER_GAS_REBATE_USD");

    // POOL - ASSET
    bytes32 constant SYMBOL = keccak256("SYMBOL");
    bytes32 constant DECIMALS = keccak256("DECIMALS");
    bytes32 constant TOKEN_ADDRESS = keccak256("TOKEN_ADDRESS");
    bytes32 constant LOT_SIZE = keccak256("LOT_SIZE");

    bytes32 constant INITIAL_MARGIN_RATE = keccak256("INITIAL_MARGIN_RATE"); // 1e5
    bytes32 constant MAINTENANCE_MARGIN_RATE = keccak256("MAINTENANCE_MARGIN_RATE"); // 1e5
    bytes32 constant MIN_PROFIT_RATE = keccak256("MIN_PROFIT_RATE"); // 1e5
    bytes32 constant MIN_PROFIT_TIME = keccak256("MIN_PROFIT_TIME"); // 1e0
    bytes32 constant POSITION_FEE_RATE = keccak256("POSITION_FEE_RATE"); // 1e5
    bytes32 constant LIQUIDATION_FEE_RATE = keccak256("LIQUIDATION_FEE_RATE"); // 1e5

    bytes32 constant REFERENCE_ORACLE = keccak256("REFERENCE_ORACLE");
    bytes32 constant REFERENCE_DEVIATION = keccak256("REFERENCE_DEVIATION"); // 1e5
    bytes32 constant REFERENCE_ORACLE_TYPE = keccak256("REFERENCE_ORACLE_TYPE");

    bytes32 constant MAX_LONG_POSITION_SIZE = keccak256("MAX_LONG_POSITION_SIZE");
    bytes32 constant MAX_SHORT_POSITION_SIZE = keccak256("MAX_SHORT_POSITION_SIZE");
    bytes32 constant FUNDING_ALPHA = keccak256("FUNDING_ALPHA");
    bytes32 constant FUNDING_BETA_APY = keccak256("FUNDING_BETA_APY"); // 1e5

    bytes32 constant LIQUIDITY_CAP_USD = keccak256("LIQUIDITY_CAP_USD");

    // ADL
    bytes32 constant ADL_RESERVE_RATE = keccak256("ADL_RESERVE_RATE"); // 1e5
    bytes32 constant ADL_MAX_PNL_RATE = keccak256("ADL_MAX_PNL_RATE"); // 1e5
    bytes32 constant ADL_TRIGGER_RATE = keccak256("ADL_TRIGGER_RATE"); // 1e5

    // ORDERBOOK
    bytes32 constant OB_LIQUIDITY_LOCK_PERIOD = keccak256("OB_LIQUIDITY_LOCK_PERIOD"); // 1e0
    bytes32 constant OB_REFERRAL_MANAGER = keccak256("OB_REFERRAL_MANAGER");
    bytes32 constant OB_MARKET_ORDER_TIMEOUT = keccak256("OB_MARKET_ORDER_TIMEOUT"); // 1e0
    bytes32 constant OB_LIMIT_ORDER_TIMEOUT = keccak256("OB_LIMIT_ORDER_TIMEOUT"); // 1e0
    bytes32 constant OB_CALLBACK_GAS_LIMIT = keccak256("OB_CALLBACK_GAS_LIMIT"); // 1e0
    bytes32 constant OB_CANCEL_COOL_DOWN = keccak256("OB_CANCEL_COOL_DOWN"); // 1e0
}
