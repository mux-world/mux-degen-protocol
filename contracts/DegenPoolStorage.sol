// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./interfaces/IDistributor.sol";
import "./interfaces/IDegenPoolStorage.sol";
import "./libraries/LibPoolStorage.sol";
import "./libraries/LibReferenceOracle.sol";
import "./libraries/LibTypeCast.sol";
import "./Types.sol";
import "./third-party/Diamond.sol";

/**
 * @dev this contract just holds the storage. all functions are in the ./facets/*.sol.
 *      you are probably looking for ./interfaces/IDegenPool.sol.
 *
 *      note: do not write a public function here, because we do not deploy this contract.
 */
contract DegenPoolStorage is Initializable, ContextUpgradeable, ReentrancyGuardUpgradeable, IDegenPoolStorage {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for uint256;
    using LibPoolStorage for PoolStorage;
    using LibAsset for Asset;
    using LibReferenceOracle for PoolStorage;

    PoolStorage internal _storage;
    bytes32[20] __gaps;

    modifier updateSequence() {
        _;
        unchecked {
            _storage.sequence += 1;
        }
        emit UpdateSequence(_storage.sequence);
    }

    modifier updateBrokerTransactions() {
        _;
        unchecked {
            _storage.brokerTransactions += 1;
        }
    }

    modifier onlyDiamondOwner() {
        require(_diamondOwner() == _msgSender(), "OWN"); // not OWNer
        _;
    }

    modifier onlyOrderBook() {
        require(_msgSender() == _storage.orderBook(), "BOK");
        _;
    }

    function _blockTimestamp() internal view virtual returns (uint32) {
        return uint32(block.timestamp);
    }

    // @dev set token.spotLiquidity -= wadAmount outside this function
    function _collectFee(uint8 tokenId, address trader, uint96 wadAmount) internal {
        emit CollectedFee(tokenId, wadAmount);
        Asset storage collateral = _storage.assets[tokenId];
        require(collateral.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        address tokenAddress = collateral.tokenAddress();
        uint256 rawAmount = collateral.toRaw(wadAmount);
        address distributor = _storage.feeDistributor();
        IERC20Upgradeable(tokenAddress).safeTransfer(distributor, rawAmount);
        IDistributor(distributor).updateRewards(tokenId, tokenAddress, trader, rawAmount.toUint96());
    }

    function _diamondOwner() internal view returns (address) {
        return LibDiamond.contractOwner();
    }

    function _checkAllMarkPrices(uint96[] memory markPrices) internal returns (uint96[] memory) {
        uint256 assetCount = _storage.assetsCount;
        require(markPrices.length == assetCount, "LEN"); // LENgth is different
        for (uint256 i = 0; i < assetCount; i++) {
            Asset storage asset = _storage.assets[i];
            markPrices[i] = _storage.checkPrice(asset, markPrices[i]);
        }
        return markPrices;
    }
}
