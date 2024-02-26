// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../interfaces/IDegenPool.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IReferralTiers.sol";
import "../interfaces/IReferralManager.sol";
import "../libraries/LibTypeCast.sol";
import "../libraries/LibConfigKeys.sol";
import "../libraries/LibTypeCast.sol";

contract DegenFeeDistributor is Initializable, IDistributor, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for uint256;
    using LibTypeCast for bytes32;

    event SetMaintainer(address newMaintainer, bool enable);
    event FeeDistributedToLP(uint8 indexed tokenId, uint256 rawAmount);
    event FeeDistributedAsDiscount(uint8 indexed tokenId, address indexed trader, uint256 rawAmount);
    event FeeDistributedAsRebate(uint8 indexed tokenId, address indexed trader, uint256 rawAmount);
    event FeeDistributedToPOL(uint8 indexed tokenId, uint256 rawAmount);
    event FeeDistributedToVe(uint8 indexed tokenId, uint256 rawAmount);
    event ClaimVeReward(uint8 indexed tokenId, uint256 rawAmount);

    IDegenPool public degenPool;
    IOrderBook public orderBook;
    IReferralManager public referralManager;
    IReferralTiers public referralTiers;
    address public protocolLiquidityOwner;
    IERC20Upgradeable public mlp;
    mapping(uint8 => uint256) public unclaimedVeReward; // tokenId => rawAmount
    mapping(address => bool) public maintainers;

    function initialize(
        address degenPool_,
        address orderBook_,
        address referralManager_,
        address referralTiers_,
        address pol_,
        address mlp_
    ) external initializer {
        __Ownable_init();
        degenPool = IDegenPool(degenPool_);
        orderBook = IOrderBook(orderBook_);
        referralManager = IReferralManager(referralManager_);
        referralTiers = IReferralTiers(referralTiers_);
        protocolLiquidityOwner = pol_;
        mlp = IERC20Upgradeable(mlp_);
    }

    function setMaintainer(address newMaintainer, bool enable) external onlyOwner {
        maintainers[newMaintainer] = enable;
        emit SetMaintainer(newMaintainer, enable);
    }

    /**
     * @dev DegenPool can distribute rewards to the trader and the referrer.
     *
     *      1. handle discount, rebate
     *      2. income × 70% × (1 - %DegenPOR)   => DLP holder    (immediately transfer)
     *      3. income × 15%                     => POL           (immediately transfer)
     *      4. income × (70% × %DegenPOR + 15%) => veMUX holders (saved in this contract until claimed)
     *      NOTE: we assume that the fees are already transferred to this contract.
     */
    function updateRewards(uint8 tokenId, address tokenAddress, address trader, uint96 rawAmount) external override {
        require(msg.sender == address(degenPool), "SND"); // SeNDer is not DegenPool
        rawAmount = _discountRebate(tokenId, tokenAddress, trader, rawAmount);
        _distributeRemaining(tokenId, tokenAddress, rawAmount);
    }

    function _discountRebate(
        uint8 tokenId,
        address tokenAddress,
        address trader,
        uint96 rawAmount
    ) internal returns (uint96 remainingRawAmount) {
        (, address codeRecipient, , uint32 discountRate, uint32 rebateRate) = getCodeOf(trader);

        uint256 rawAmountToTrader = (uint256(rawAmount) * uint256(discountRate)) / 1e5;
        if (trader == address(0)) {
            // this should never happen, but just in case
            rawAmountToTrader = 0;
        }
        if (rawAmountToTrader > 0) {
            emit FeeDistributedAsDiscount(tokenId, trader, rawAmountToTrader);
        }

        uint256 rawAmountToReferrer = (uint256(rawAmount) * uint256(rebateRate)) / 1e5;
        if (codeRecipient == address(0)) {
            rawAmountToReferrer = 0;
        }
        if (rawAmountToReferrer > 0) {
            emit FeeDistributedAsRebate(tokenId, trader, rawAmountToReferrer);
        }

        if (trader == codeRecipient && trader != address(0)) {
            // merged
            uint256 total = rawAmountToTrader + rawAmountToReferrer;
            IERC20Upgradeable(tokenAddress).safeTransfer(trader, total);
        } else {
            // separated
            if (rawAmountToTrader > 0) {
                IERC20Upgradeable(tokenAddress).safeTransfer(trader, rawAmountToTrader);
            }
            if (rawAmountToReferrer > 0) {
                IERC20Upgradeable(tokenAddress).safeTransfer(codeRecipient, rawAmountToReferrer);
            }
        }
        return (uint256(rawAmount) - rawAmountToTrader - rawAmountToReferrer).toUint96();
    }

    function _distributeRemaining(uint8 tokenId, address tokenAddress, uint96 rawAmount) internal {
        // income × 70% × (1 - %DegenPOR) => DLP holder
        uint256 por = poolOwnedRate(); // 1e18
        uint256 rawAmountToLP = (uint256(rawAmount) * (1e18 - por) * 7) / 10 / 1e18;
        if (rawAmountToLP > 0) {
            IERC20Upgradeable(tokenAddress).approve(address(orderBook), rawAmountToLP);
            orderBook.donateLiquidity(tokenId, rawAmountToLP.toUint96());
            emit FeeDistributedToLP(tokenId, rawAmountToLP);
        }

        // income × 15% => POL
        uint256 rawAmountToPOL = (uint256(rawAmount) * 15) / 100;
        if (rawAmountToPOL > 0) {
            IERC20Upgradeable(tokenAddress).safeTransfer(protocolLiquidityOwner, rawAmountToPOL);
            emit FeeDistributedToPOL(tokenId, rawAmountToPOL);
        }

        // remaining => veMUX holders
        uint256 rawAmountToVe = uint256(rawAmount) - rawAmountToLP - rawAmountToPOL;
        if (rawAmountToVe > 0) {
            unclaimedVeReward[tokenId] += rawAmountToVe;
            emit FeeDistributedToVe(tokenId, rawAmountToVe);
        }
    }

    function claimVeReward(uint8 tokenId) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        address tokenAddress = degenPool.getAssetParameter(tokenId, LibConfigKeys.TOKEN_ADDRESS).toAddress();
        uint256 amount = unclaimedVeReward[tokenId];
        SafeERC20Upgradeable.safeTransfer(IERC20Upgradeable(tokenAddress), msg.sender, amount);
        unclaimedVeReward[tokenId] = 0;
        emit ClaimVeReward(tokenId, amount);
    }

    /**
     * @dev The referral code determines the discount and rebate rates.
     */
    function getCodeOf(
        address trader
    ) public view returns (bytes32 code, address codeRecipient, uint256 tier, uint32 discountRate, uint32 rebateRate) {
        (code, ) = referralManager.getReferralCodeOf(trader);
        if (code != bytes32(0)) {
            codeRecipient = referralManager.rebateRecipients(code);
            tier = referralTiers.code2Tier(code);
            (, , uint64 rate1, uint64 rate2) = referralManager.tierSettings(tier);
            discountRate = uint256(rate1).toUint32();
            rebateRate = uint256(rate2).toUint32();
        } else {
            // empty referral code is not tier 0, but zero discount/rebate
        }
    }

    // 1e18
    function poolOwnedRate() public view returns (uint256) {
        uint256 numerator = IERC20Upgradeable(mlp).balanceOf(protocolLiquidityOwner);
        uint256 denominator = IERC20Upgradeable(mlp).totalSupply();
        return denominator == 0 ? 0 : (numerator * 1e18) / denominator;
    }
}
