// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../interfaces/IDegenPool.sol";
import "../libraries/LibConfigKeys.sol";
import "../libraries/LibTypeCast.sol";

contract Reader {
    using LibTypeCast for bytes32;

    struct AssetStorage {
        uint8 id;
        // config
        bytes32 symbol;
        address tokenAddress; // erc20.address
        uint256 decimals; // erc20.decimals
        uint96 lotSize; // 1e18. ex: lotSize = 0.1, the order amount must be 0.1, 0.2, ...
        uint32 initialMarginRate; // 1e5
        uint32 maintenanceMarginRate; // 1e5
        uint32 positionFeeRate; // 1e5
        uint32 liquidationFeeRate; // 1e5
        uint32 minProfitRate; // 1e5
        uint32 minProfitTime; // 1e0
        uint96 maxLongPositionSize;
        uint96 maxShortPositionSize;
        uint96 fundingAlpha; // 1e18
        uint32 fundingBetaApy; // 1e5
        uint32 referenceOracleType;
        address referenceOracle;
        uint32 referenceDeviation;
        uint32 adlReserveRate; // 1e5
        uint32 adlMaxPnlRate; // 1e5
        uint32 adlTriggerRate; // 1e5
        // storage
        uint56 flags; // a bitset of ASSET_*
        uint96 spotLiquidity;
        uint96 totalLongPosition;
        uint96 averageLongPrice;
        uint96 totalShortPosition;
        uint96 averageShortPrice;
        uint128 longCumulativeFunding;
        uint128 shortCumulativeFunding;
    }

    struct SubAccountState {
        uint96 collateral;
        uint96 size;
        uint32 lastIncreasedTime;
        uint96 entryPrice;
        uint128 entryFunding;
    }

    IDegenPool public pool;

    constructor(IDegenPool pool_) {
        pool = pool_;
    }

    function getAssets() public returns (AssetStorage[] memory ret) {
        pool.updateFundingState(); // update asset *CumulativeFunding
        (uint8 assetsCount, , , ) = pool.getPoolStorage();
        ret = new AssetStorage[](assetsCount);
        for (uint8 i = 0; i < assetsCount; i++) {
            ret[i].id = i;
            {
                (
                    uint56 flags,
                    uint96 spotLiquidity,
                    uint96 totalLongPosition,
                    uint96 averageLongPrice,
                    uint96 totalShortPosition,
                    uint96 averageShortPrice,
                    uint128 longCumulativeFunding,
                    uint128 shortCumulativeFunding
                ) = pool.getAssetStorageV2(i);
                ret[i].flags = flags;
                ret[i].spotLiquidity = spotLiquidity;
                ret[i].totalLongPosition = totalLongPosition;
                ret[i].averageLongPrice = averageLongPrice;
                ret[i].totalShortPosition = totalShortPosition;
                ret[i].averageShortPrice = averageShortPrice;
                ret[i].longCumulativeFunding = longCumulativeFunding;
                ret[i].shortCumulativeFunding = shortCumulativeFunding;
            }
            ret[i].symbol = pool.getAssetParameter(i, LibConfigKeys.SYMBOL);
            ret[i].tokenAddress = pool.getAssetParameter(i, LibConfigKeys.TOKEN_ADDRESS).toAddress();
            ret[i].decimals = pool.getAssetParameter(i, LibConfigKeys.DECIMALS).toUint256();
            ret[i].lotSize = pool.getAssetParameter(i, LibConfigKeys.LOT_SIZE).toUint96();
            ret[i].initialMarginRate = pool.getAssetParameter(i, LibConfigKeys.INITIAL_MARGIN_RATE).toUint32();
            ret[i].maintenanceMarginRate = pool.getAssetParameter(i, LibConfigKeys.MAINTENANCE_MARGIN_RATE).toUint32();
            ret[i].positionFeeRate = pool.getAssetParameter(i, LibConfigKeys.POSITION_FEE_RATE).toUint32();
            ret[i].liquidationFeeRate = pool.getAssetParameter(i, LibConfigKeys.LIQUIDATION_FEE_RATE).toUint32();
            ret[i].minProfitRate = pool.getAssetParameter(i, LibConfigKeys.MIN_PROFIT_RATE).toUint32();
            ret[i].minProfitTime = pool.getAssetParameter(i, LibConfigKeys.MIN_PROFIT_TIME).toUint32();
            ret[i].maxLongPositionSize = pool.getAssetParameter(i, LibConfigKeys.MAX_LONG_POSITION_SIZE).toUint96();
            ret[i].maxShortPositionSize = pool.getAssetParameter(i, LibConfigKeys.MAX_SHORT_POSITION_SIZE).toUint96();
            ret[i].fundingAlpha = pool.getAssetParameter(i, LibConfigKeys.FUNDING_ALPHA).toUint96();
            ret[i].fundingBetaApy = pool.getAssetParameter(i, LibConfigKeys.FUNDING_BETA_APY).toUint32();
            ret[i].referenceOracleType = pool.getAssetParameter(i, LibConfigKeys.REFERENCE_ORACLE_TYPE).toUint32();
            ret[i].referenceOracle = pool.getAssetParameter(i, LibConfigKeys.REFERENCE_ORACLE).toAddress();
            ret[i].referenceDeviation = pool.getAssetParameter(i, LibConfigKeys.REFERENCE_DEVIATION).toUint32();
            ret[i].adlReserveRate = pool.getAssetParameter(i, LibConfigKeys.ADL_RESERVE_RATE).toUint32();
            ret[i].adlMaxPnlRate = pool.getAssetParameter(i, LibConfigKeys.ADL_MAX_PNL_RATE).toUint32();
            ret[i].adlTriggerRate = pool.getAssetParameter(i, LibConfigKeys.ADL_TRIGGER_RATE).toUint32();
        }
    }

    function getSubAccounts(bytes32[] memory subAccountIds) public view returns (SubAccountState[] memory subAccounts) {
        return _getSubAccounts(subAccountIds);
    }

    function _getSubAccounts(
        bytes32[] memory subAccountIds
    ) internal view returns (SubAccountState[] memory subAccounts) {
        subAccounts = new SubAccountState[](subAccountIds.length);
        for (uint256 i = 0; i < subAccountIds.length; i++) {
            (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding) = pool
                .getSubAccount(subAccountIds[i]);
            subAccounts[i] = SubAccountState(collateral, size, lastIncreasedTime, entryPrice, entryFunding);
        }
    }

    function getAllSubAccounts(
        uint256 begin,
        uint256 end
    ) public view returns (bytes32[] memory subAccountIds, SubAccountState[] memory subAccounts, uint256 totalCount) {
        (subAccountIds, totalCount) = pool.getSubAccountIds(begin, end);
        subAccounts = _getSubAccounts(subAccountIds);
    }

    function getSubAccountsOf(
        address trader,
        uint256 begin,
        uint256 end
    ) public view returns (bytes32[] memory subAccountIds, SubAccountState[] memory subAccounts, uint256 totalCount) {
        (subAccountIds, totalCount) = pool.getSubAccountIdsOf(trader, begin, end);
        subAccounts = _getSubAccounts(subAccountIds);
    }
}
