// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IDegenPool.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IReferralTiers.sol";
import "../interfaces/IReferralManager.sol";
import "../libraries/LibTypeCast.sol";

interface IOrderBook {
    function donateLiquidity(
        uint8 assetId,
        uint96 rawAmount // erc20.decimals
    ) external;
}

contract DegenFeeDistributor is Initializable, IDistributor {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for uint256;

    event FeeDistributed(
        uint8 indexed tokenId,
        address indexed trader,
        uint256 rawAmountToPool,
        uint256 rawAmountToTrader,
        uint256 rawAmountToReferrer
    );

    IDegenPool public degenPool;
    IOrderBook public orderBook;
    IReferralManager public referralManager;
    IReferralTiers public referralTiers;

    function initialize(
        address degenPool_,
        address orderBook_,
        address referralManager_,
        address referralTiers_
    ) external initializer {
        degenPool = IDegenPool(degenPool_);
        orderBook = IOrderBook(orderBook_);
        referralManager = IReferralManager(referralManager_);
        referralTiers = IReferralTiers(referralTiers_);
    }

    /**
     * @dev Distribute rewards to the trader and the referrer
     *
     *      NOTE: we assume that the fees are already transferred to this contract.
     */
    function updateRewards(uint8 tokenId, address tokenAddress, address trader, uint96 rawAmount) external override {
        require(msg.sender == address(degenPool), "SND"); // SeNDer is not DegenPool
        (, address codeRecipient, , uint32 discountRate, uint32 rebateRate) = getCodeOf(trader);
        uint256 rawAmountToTrader = (uint256(rawAmount) * uint256(discountRate)) / 1e5;
        if (trader == address(0)) {
            // this should never happen, but just in case
            rawAmountToTrader = 0;
        }
        uint256 rawAmountToReferrer = (uint256(rawAmount) * uint256(rebateRate)) / 1e5;
        if (codeRecipient == address(0)) {
            // this should never happen, but just in case
            rawAmountToReferrer = 0;
        }
        uint256 rawAmountToPool = rawAmount - rawAmountToTrader - rawAmountToReferrer;
        if (rawAmountToPool > 0) {
            IERC20Upgradeable(tokenAddress).approve(address(orderBook), rawAmountToPool);
            orderBook.donateLiquidity(tokenId, rawAmountToPool.toUint96());
        }
        if (rawAmountToTrader > 0) {
            IERC20Upgradeable(tokenAddress).safeTransfer(trader, rawAmountToTrader);
        }
        if (rawAmountToReferrer > 0) {
            IERC20Upgradeable(tokenAddress).safeTransfer(codeRecipient, rawAmountToReferrer);
        }
        emit FeeDistributed(tokenId, trader, rawAmountToPool, rawAmountToTrader, rawAmountToReferrer);
    }

    function getCodeOf(
        address trader
    ) public returns (bytes32 code, address codeRecipient, uint256 tier, uint32 discountRate, uint32 rebateRate) {
        (code, ) = referralManager.getReferralCodeOf(trader);
        if (code != bytes32(0)) {
            codeRecipient = referralManager.rebateRecipients(code);
            tier = referralTiers.code2Tier(code);
            (, , uint64 rate1, uint64 rate2) = referralManager.tierSettings(tier);
            discountRate = uint256(rate1).toUint32();
            rebateRate = uint256(rate2).toUint32();
        } else {
            // empty referral code is not even a tier 0
        }
    }
}
