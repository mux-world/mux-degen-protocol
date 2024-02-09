// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

// funding period
uint32 constant APY_PERIOD = 86400 * 365;

// flags
uint56 constant ASSET_IS_STABLE = 0x00000000000001; // is a usdt, usdc, ...
uint56 constant ASSET_CAN_ADD_REMOVE_LIQUIDITY = 0x00000000000002; // can call addLiquidity and removeLiquidity with this token
uint56 constant ASSET_IS_TRADABLE = 0x00000000000100; // allowed to be assetId
uint56 constant ASSET_IS_OPENABLE = 0x00000000010000; // can open position
uint56 constant ASSET_IS_SHORTABLE = 0x00000001000000; // allow shorting this asset
uint56 constant ASSET_IS_ENABLED = 0x00010000000000; // allowed to be assetId and collateralId
uint56 constant ASSET_IS_STRICT_STABLE = 0x01000000000000; // assetPrice is always 1 unless volatility exceeds strictStableDeviation

enum ReferenceOracleType {
    None,
    Chainlink
}

struct PoolStorage {
    // configs
    mapping(uint256 => Asset) assets;
    mapping(bytes32 => SubAccount) accounts;
    mapping(address => bool) maintainers;
    mapping(bytes32 => bytes32) parameters;
    // status
    mapping(address => EnumerableSetUpgradeable.Bytes32Set) userSubAccountIds;
    EnumerableSetUpgradeable.Bytes32Set isMaintenanceParameters;
    uint8 assetsCount;
    uint32 sequence;
    uint32 lastFundingTime;
    uint32 brokerTransactions;
    EnumerableSetUpgradeable.Bytes32Set subAccountIds;
    bytes32[20] __gaps;
}

struct Asset {
    // configs
    uint8 id;
    mapping(bytes32 => bytes32) parameters;
    EnumerableSetUpgradeable.Bytes32Set isMaintenanceParameters;
    // status
    uint56 flags;
    uint96 spotLiquidity;
    uint96 __deleted0;
    uint96 totalLongPosition;
    uint96 averageLongPrice;
    uint96 totalShortPosition;
    uint96 averageShortPrice;
    uint128 longCumulativeFunding; // Σ_t fundingRate_t + borrowingRate_t. 1e18. payment = (cumulative - entry) * positionSize * entryPrice
    uint128 shortCumulativeFunding; // Σ_t fundingRate_t + borrowingRate_t. 1e18. payment = (cumulative - entry) * positionSize * entryPrice
}

struct SubAccount {
    uint96 collateral;
    uint96 size;
    uint32 lastIncreasedTime;
    uint96 entryPrice;
    uint128 entryFunding; // entry longCumulativeFunding for long position. entry shortCumulativeFunding for short position
}
