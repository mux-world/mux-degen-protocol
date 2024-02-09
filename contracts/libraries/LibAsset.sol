// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";

import "../libraries/LibConfigKeys.sol";
import "../libraries/LibTypeCast.sol";
import "../libraries/LibMath.sol";
import "../Types.sol";
import "../libraries/LibAsset.sol";

library LibAsset {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;
    using LibMath for uint256;
    using LibTypeCast for bytes32;
    using LibTypeCast for uint256;
    using LibConfigKeys for bytes32;

    function symbol(Asset storage asset) internal view returns (bytes32) {
        return asset.parameters[LibConfigKeys.SYMBOL];
    }

    function decimals(Asset storage asset) internal view returns (uint256) {
        return asset.parameters[LibConfigKeys.DECIMALS].toUint256();
    }

    function tokenAddress(Asset storage asset) internal view returns (address) {
        return asset.parameters[LibConfigKeys.TOKEN_ADDRESS].toAddress();
    }

    function initialMarginRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.INITIAL_MARGIN_RATE].toUint32();
    }

    function maintenanceMarginRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.MAINTENANCE_MARGIN_RATE].toUint32();
    }

    function minProfitRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.MIN_PROFIT_RATE].toUint32();
    }

    function minProfitTime(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.MIN_PROFIT_TIME].toUint32();
    }

    function positionFeeRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.POSITION_FEE_RATE].toUint32();
    }

    function liquidationFeeRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.LIQUIDATION_FEE_RATE].toUint32();
    }

    function referenceOracle(Asset storage asset) internal view returns (address) {
        return asset.parameters[LibConfigKeys.REFERENCE_ORACLE].toAddress();
    }

    function referenceDeviation(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.REFERENCE_DEVIATION].toUint32();
    }

    function referenceOracleType(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.REFERENCE_ORACLE_TYPE].toUint32();
    }

    function fundingAlpha(Asset storage asset) internal view returns (uint96) {
        return asset.parameters[LibConfigKeys.FUNDING_ALPHA].toUint96();
    }

    function fundingBetaApy(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.FUNDING_BETA_APY].toUint32();
    }

    function maxLongPositionSize(Asset storage asset) internal view returns (uint96) {
        return asset.parameters[LibConfigKeys.MAX_LONG_POSITION_SIZE].toUint96();
    }

    function maxShortPositionSize(Asset storage asset) internal view returns (uint96) {
        return asset.parameters[LibConfigKeys.MAX_SHORT_POSITION_SIZE].toUint96();
    }

    function adlReserveRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.ADL_RESERVE_RATE].toUint32();
    }

    function adlMaxPnlRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.ADL_MAX_PNL_RATE].toUint32();
    }

    function adlTriggerRate(Asset storage asset) internal view returns (uint32) {
        return asset.parameters[LibConfigKeys.ADL_TRIGGER_RATE].toUint32();
    }

    function toWad(Asset storage asset, uint256 rawAmount) internal view returns (uint96) {
        return (rawAmount * (10 ** (18 - decimals(asset)))).toUint96();
    }

    function toRaw(Asset storage asset, uint96 wadAmount) internal view returns (uint256) {
        return uint256(wadAmount) / 10 ** (18 - decimals(asset));
    }

    // is a usdt, usdc, ...
    function isStable(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_STABLE) != 0;
    }

    // can call addLiquidity and removeLiquidity with this token
    function canAddRemoveLiquidity(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_CAN_ADD_REMOVE_LIQUIDITY) != 0;
    }

    // allowed to be assetId
    function isTradable(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_TRADABLE) != 0;
    }

    // can open position
    function isOpenable(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_OPENABLE) != 0;
    }

    // allow shorting this asset
    function isShortable(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_SHORTABLE) != 0;
    }

    // allowed to be assetId and collateralId
    function isEnabled(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_ENABLED) != 0;
    }

    // assetPrice is always 1 unless volatility exceeds strictStableDeviation
    function isStrictStable(Asset storage asset) internal view returns (bool) {
        return (asset.flags & ASSET_IS_STRICT_STABLE) != 0;
    }

    // ex: lotSize = 0.1, positionOrderAmount should be 0.1, 0.2, 0.3, ...
    function lotSize(Asset storage asset) internal view returns (uint96) {
        return asset.parameters[LibConfigKeys.LOT_SIZE].toUint96();
    }

    function transferOut(Asset storage asset, address recipient, uint256 rawAmount) internal {
        // commented: if tokenAddress(asset) == weth
        IERC20Upgradeable(tokenAddress(asset)).safeTransfer(recipient, rawAmount);
    }
}
