// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "../interfaces/IDegenPool.sol";
import "../libraries/LibConfigKeys.sol";

contract MockDegenPool is IDegenPool {
    /////////////////////////////////////////////////////////////////////////////////
    //                              mock
    mapping(uint8 => address) public mockAssetAddress;
    mapping(uint8 => uint32) public mockMinProfitTime;
    mapping(uint8 => uint32) public mockMinProfitRate;
    mapping(uint8 => uint96) public mockLotSize;
    mapping(uint8 => uint56) public mockFlags;
    mapping(bytes32 => SubAccount) public mockSubAccounts;

    function setAssetAddress(uint8 assetId, address tokenAddress) external {
        mockAssetAddress[assetId] = tokenAddress;
    }

    function setAssetParams(
        uint8 assetId,
        uint32 newMinProfitTime,
        uint32 newMinProfitRate,
        uint96 newLotSize
    ) external {
        mockMinProfitTime[assetId] = newMinProfitTime;
        mockMinProfitRate[assetId] = newMinProfitRate;
        mockLotSize[assetId] = newLotSize;
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                                 getters

    function diamondOwner() external pure returns (address) {
        return address(0);
    }

    function getPoolParameter(bytes32 key) external pure returns (bytes32) {
        key;
        return bytes32(0);
    }

    function isMaintainer(address maintainer) external pure returns (bool) {
        maintainer;
        return false;
    }

    function getMaintenanceParameter(bytes32 key) external pure returns (bool) {
        key;
        return false;
    }

    function getPoolStorage()
        external
        pure
        returns (uint8 assetsCount, uint32 sequence, uint32 lastFundingTime, uint32 brokerTransactions)
    {
        return (0, 0, 0, 0);
    }

    function getAssetParameter(uint8 assetId, bytes32 key) external view returns (bytes32) {
        if (key == LibConfigKeys.TOKEN_ADDRESS) {
            return bytes32(uint256(uint160(mockAssetAddress[assetId])));
        } else if (key == LibConfigKeys.MIN_PROFIT_TIME) {
            return bytes32(uint256(uint32(mockMinProfitTime[assetId])));
        } else if (key == LibConfigKeys.MIN_PROFIT_RATE) {
            return bytes32(uint256(uint32(mockMinProfitRate[assetId])));
        } else if (key == LibConfigKeys.LOT_SIZE) {
            return bytes32(uint256(mockLotSize[assetId]));
        }
        return bytes32(0);
    }

    function getAssetFlags(uint8 assetId) external view returns (uint56) {
        return mockFlags[assetId];
    }

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
        )
    {
        flags = mockFlags[assetId];
        return (flags, 0, 0, 0, 0, 0, 0, 0);
    }

    function getSubAccount(
        bytes32 subAccountId
    )
        external
        view
        returns (uint96 collateral, uint96 size, uint32 lastIncreasedTime, uint96 entryPrice, uint128 entryFunding)
    {
        SubAccount storage subAccount = mockSubAccounts[subAccountId];
        collateral = subAccount.collateral;
        size = subAccount.size;
        lastIncreasedTime = subAccount.lastIncreasedTime;
        entryPrice = subAccount.entryPrice;
        entryFunding = subAccount.entryFunding;
    }

    function traderPnl(
        bytes32 subAccountId,
        uint96 price
    ) external pure returns (bool hasProfit, uint96 positionPnlUsd, uint96 cappedPnlUsd) {
        subAccountId;
        price;
        return (false, 0, 0);
    }

    function isDeleverageAllowed(bytes32 subAccountId, uint96 markPrice) external pure returns (bool) {
        subAccountId;
        markPrice;
        return false;
    }

    function isAboveTargetAdlRate(bytes32 subAccountId, uint96 markPrice) external pure returns (bool) {
        subAccountId;
        markPrice;
        return false;
    }

    function getSubAccountIds(
        uint256 begin,
        uint256 end
    ) external pure returns (bytes32[] memory subAccountIds, uint256 totalCount) {
        begin;
        end;
        return (new bytes32[](0), 0);
    }

    function getSubAccountIdsOf(
        address trader,
        uint256 begin,
        uint256 end
    ) external pure returns (bytes32[] memory subAccountIds, uint256 totalCount) {
        trader;
        begin;
        end;
        return (new bytes32[](0), 0);
    }

    function getMlpPrice(uint96[] memory markPrices) external pure returns (uint96 mlpPrice) {
        markPrices;
        return 0;
    }

    /////////////////////////////////////////////////////////////////////////////////
    //                             for Trader / Broker

    function withdrawAllCollateral(bytes32 subAccountId) external {}

    /////////////////////////////////////////////////////////////////////////////////
    //                                 only Broker

    function depositCollateral(
        bytes32 subAccountId,
        uint256 rawAmount // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
    ) external {}

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external {}

    function withdrawProfit(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint8 profitAssetId, // only used when !isLong
        uint96[] memory markPrices
    ) external {}

    /**
     * @dev   Add liquidity.
     *
     * @param trader            liquidity provider address.
     * @param tokenId           asset.id that added.
     * @param rawAmount         asset token amount. decimals = erc20.decimals.
     * @param markPrices       asset prices of all supported assets.
     */
    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint256 rawAmount, // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
        uint96[] memory markPrices
    ) external pure returns (uint96 mlpAmount) {
        trader;
        tokenId;
        rawAmount;
        markPrices;
        return 0;
    }

    /**
     * @dev Add liquidity but ignore MLP
     */
    function donateLiquidity(address who, uint8 tokenId, uint256 rawAmount) external pure {
        who;
        tokenId;
        rawAmount;
    }

    /**
     * @dev   Remove liquidity.
     *
     * @param trader            liquidity provider address.
     * @param mlpAmount         mlp amount.
     * @param tokenId           asset.id that removed to.
     * @param markPrices       asset prices of all supported assets.
     */
    function removeLiquidity(
        address trader,
        uint96 mlpAmount, // NOTE: OrderBook SHOULD transfer mlpAmount mlp to LiquidityPool
        uint8 tokenId,
        uint96[] memory markPrices
    ) external pure returns (uint256 rawAmount) {
        trader;
        tokenId;
        mlpAmount;
        markPrices;
        return 0;
    }

    /**
     * @notice Open a position.
     *
     * @param  subAccountId     check LibSubAccount.decodeSubAccountId for detail.
     * @param  amount           filled position size. decimals = 18.
     * @param  tradingPrice     price of subAccount.asset. decimals = 18.
     * @param  markPrices       mark prices of all assets. decimals = 18.
     */
    function openPosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external returns (uint96) {
        markPrices;
        mockSubAccounts[subAccountId] = SubAccount({
            collateral: amount,
            size: amount,
            lastIncreasedTime: uint32(block.timestamp),
            entryPrice: tradingPrice,
            entryFunding: 0
        });
        return tradingPrice;
    }

    /**
     * @notice Close a position.
     *
     * @param  subAccountId     check LibSubAccount.decodeSubAccountId for detail.
     * @param  amount           filled position size. decimals = 18.
     * @param  tradingPrice     price of subAccount.asset. decimals = 18.
     * @param  profitAssetId    for long position (unless asset.useStable is true), ignore this argument;
     *                          for short position, the profit asset should be one of the stable coin.
     * @param  markPrices      mark prices of all assets. decimals = 18.
     */
    function closePosition(
        bytes32 subAccountId,
        uint96 amount,
        uint96 tradingPrice,
        uint8 profitAssetId, // only used when !isLong
        uint96[] memory markPrices
    ) external pure returns (uint96) {
        subAccountId;
        amount;
        profitAssetId;
        markPrices;
        return tradingPrice;
    }

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _updateFundingState in Liquidity.sol and _getBorrowing in Trade.sol
     *         on how to calculate funding and borrowing.
     */
    function updateFundingState() external pure {}

    function liquidate(
        bytes32 subAccountId,
        uint8 profitAssetId, // only used when !isLong
        uint96 tradingPrice,
        uint96[] memory markPrices
    ) external pure returns (uint96) {
        subAccountId;
        profitAssetId;
        tradingPrice;
        markPrices;
        return 0;
    }

    /**
     * @dev Broker can withdraw brokerGasRebate.
     */
    function claimBrokerGasRebate(address receiver, uint8 assetId) external pure returns (uint256 rawAmount) {
        receiver;
        assetId;
        return 0;
    }

    /**
     * @dev Sets the maintainer address.
     * @param newMaintainer The new maintainer address.
     * @param enable Whether the maintainer is enabled or disabled.
     */
    function setMaintainer(address newMaintainer, bool enable) external {}

    /**
     * @dev Sets the maintenance parameters.
     * @param key The key of the maintenance parameter.
     * @param enable Whether the maintenance parameter is enabled or disabled.
     */
    function setMaintenanceParameters(bytes32 key, bool enable) external {}

    /**
     * @dev Adds a new asset.
     * @param assetId The ID of the new asset.
     * @param keys The keys of the asset parameters.
     * @param values The values of the asset parameters.
     */
    function addAsset(uint8 assetId, bytes32[] calldata keys, bytes32[] calldata values) external {}

    /**
     * @dev Sets the pool parameters.
     * @param keys The keys of the pool parameters.
     * @param values The values of the pool parameters.
     * @param currentValues The current values of the pool parameters.
     */
    function setPoolParameters(
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues
    ) external {}

    /**
     * @dev Sets the asset parameters.
     * @param assetId The ID of the asset.
     * @param keys The keys of the asset parameters.
     * @param values The values of the asset parameters.
     * @param currentValues The current values of the asset parameters.
     */
    function setAssetParameters(
        uint8 assetId,
        bytes32[] calldata keys,
        bytes32[] calldata values,
        bytes32[] calldata currentValues
    ) external {}

    /**
     * @dev Sets the asset flags.
     * @param assetId The ID of the asset.
     * @param isTradable Whether the asset is tradable.
     * @param isOpenable Whether the asset is openable.
     * @param isShortable Whether the asset is shortable.
     * @param isEnabled Whether the asset is enabled.
     * @param isStable Whether the asset is stable.
     * @param isStrictStable Whether the asset is strictly stable.
     * @param canAddRemoveLiquidity Whether liquidity can be added or removed for the asset.
     */
    function setAssetFlags(
        uint8 assetId,
        bool isTradable,
        bool isOpenable,
        bool isShortable,
        bool isEnabled,
        bool isStable,
        bool isStrictStable,
        bool canAddRemoveLiquidity
    ) external {
        uint56 newFlags;
        newFlags |= (isTradable ? ASSET_IS_TRADABLE : 0);
        newFlags |= (isOpenable ? ASSET_IS_OPENABLE : 0);
        newFlags |= (isShortable ? ASSET_IS_SHORTABLE : 0);
        newFlags |= (isEnabled ? ASSET_IS_ENABLED : 0);
        newFlags |= (isStable ? ASSET_IS_STABLE : 0);
        newFlags |= (isStrictStable ? ASSET_IS_STRICT_STABLE : 0);
        newFlags |= (canAddRemoveLiquidity ? ASSET_CAN_ADD_REMOVE_LIQUIDITY : 0);
        mockFlags[assetId] = newFlags;
    }
}
