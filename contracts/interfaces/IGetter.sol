// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity 0.8.19;

interface IGetter {
    function diamondOwner() external view returns (address);

    function getPoolParameter(bytes32 key) external view returns (bytes32);

    function isMaintainer(address maintainer) external view returns (bool);

    function getMaintenanceParameter(bytes32 key) external view returns (bool);

    function getPoolStorage()
        external
        view
        returns (uint8 assetsCount, uint32 sequence, uint32 lastFundingTime, uint32 brokerTransactions);

    function getAssetParameter(uint8 assetId, bytes32 key) external view returns (bytes32);

    function getAssetFlags(uint8 assetId) external view returns (uint56);

    function getAssetStorageV2(
        uint8 assetId
    )
        external
        view
        returns (
            uint56 flags,
            uint96 spotLiquidity,
            uint96 totalLongPosition,
            uint96 averageLongPrice,
            uint96 totalShortPosition,
            uint96 averageShortPrice,
            uint128 longCumulativeFunding,
            uint128 shortCumulativeFunding
        );

    function getSubAccount(
        bytes32 subAccountId
    )
        external
        view
        returns (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding);

    function traderPnl(
        bytes32 subAccountId,
        uint96 price
    ) external returns (bool hasProfit, uint96 positionPnlUsd, uint96 cappedPnlUsd);

    function isDeleverageAllowed(bytes32 subAccountId, uint96 markPrice) external returns (bool);

    function getSubAccountIds(
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory subAccountIds, uint256 totalCount);

    function getSubAccountIdsOf(
        address trader,
        uint256 begin,
        uint256 end
    ) external view returns (bytes32[] memory subAccountIds, uint256 totalCount);

    function getMlpPrice(uint96[] memory markPrices) external returns (uint96 mlpPrice);
}
