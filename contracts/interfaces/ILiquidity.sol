// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

interface ILiquidity {
    event AddLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount,
        uint96 fee
    );

    event DonateLiquidity(address indexed who, uint8 indexed tokenId, uint96 wadAmount);

    event RemoveLiquidity(
        address indexed trader,
        uint8 indexed tokenId,
        uint96 tokenPrice,
        uint96 mlpPrice,
        uint96 mlpAmount,
        uint96 fee
    );

    event ClaimBrokerGasRebate(address indexed receiver, uint32 transactions, uint8 assetId, uint256 rawAmount);

    event UpdateFundingRate(
        uint8 indexed tokenId,
        bool isPositiveFundingRate,
        uint32 newFundingRateApy, // 1e5
        uint32 newBorrowingRateApy, // 1e5
        uint128 longCumulativeFunding, // 1e18
        uint128 shortCumulativeFunding // 1e18
    );

    /**
     * @dev   Add liquidity.
     *
     * @param trader            liquidity provider address.
     * @param tokenId           asset.id that added.
     * @param rawAmount         asset token amount. decimals = erc20.decimals.
     * @param markPrices        markPrices prices of all supported assets.
     */
    function addLiquidity(
        address trader,
        uint8 tokenId,
        uint256 rawAmount, // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
        uint96[] memory markPrices
    ) external returns (uint96 mlpAmount);

    /**
     * @dev Add liquidity but ignore MLP
     */
    function donateLiquidity(
        address who,
        uint8 tokenId,
        uint256 rawAmount // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
    ) external;

    /**
     * @dev   Remove liquidity.
     *
     * @param trader            liquidity provider address.
     * @param mlpAmount         mlp amount.
     * @param tokenId           asset.id that removed to.
     * @param markPrices        asset prices of all supported assets.
     */
    function removeLiquidity(
        address trader,
        uint96 mlpAmount,
        uint8 tokenId,
        uint96[] memory markPrices
    ) external returns (uint256 rawAmount);

    /**
     * @notice Broker can update funding each [fundingInterval] seconds by specifying utilizations.
     *
     *         Check _updateFundingState in Liquidity.sol and _getBorrowing in Trade.sol
     *         on how to calculate funding and borrowing.
     */
    function updateFundingState() external;

    /**
     * @dev Broker can withdraw brokerGasRebate.
     */
    function claimBrokerGasRebate(address receiver, uint8 assetId) external returns (uint256 rawAmount);
}
