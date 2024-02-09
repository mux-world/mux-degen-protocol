// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "../interfaces/IAccount.sol";

import "../libraries/LibSubAccount.sol";
import "../libraries/LibMath.sol";
import "../libraries/LibAsset.sol";
import "../libraries/LibReferenceOracle.sol";
import "../libraries/LibTypeCast.sol";
import "../libraries/LibPoolStorage.sol";
import "../libraries/LibAccount.sol";

import "../DegenPoolStorage.sol";

contract Account is DegenPoolStorage, IAccount {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.Bytes32Set;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using SafeMathUpgradeable for uint256;

    using LibMath for uint256;
    using LibSubAccount for bytes32;
    using LibAsset for Asset;
    using LibAccount for Asset;
    using LibPoolStorage for PoolStorage;
    using LibTypeCast for uint256;

    function depositCollateral(
        bytes32 subAccountId,
        uint256 rawAmount // NOTE: OrderBook SHOULD transfer rawAmount collateral to LiquidityPool
    ) external onlyOrderBook updateSequence {
        SubAccountId memory decoded = subAccountId.decode();
        require(decoded.account != address(0), "T=0"); // Trader address is zero
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        require(_storage.isValidAssetId(decoded.assetId), "LST"); // the asset is not LiSTed
        require(_storage.isValidAssetId(decoded.collateralId), "LST"); // the asset is not LiSTed

        SubAccount storage subAccount = _storage.accounts[subAccountId];
        Asset storage asset = _storage.assets[decoded.assetId];
        Asset storage collateral = _storage.assets[decoded.collateralId];
        require(asset.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(collateral.isEnabled(), "ENA"); // the token is temporarily not ENAbled

        uint96 wadAmount = collateral.toWad(rawAmount);
        subAccount.collateral += wadAmount;

        emit DepositCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);

        // trace
        _storage.userSubAccountIds[decoded.account].add(subAccountId);
        _storage.subAccountIds.add(subAccountId);
    }

    function withdrawCollateral(
        bytes32 subAccountId,
        uint256 rawAmount,
        uint96 collateralPrice,
        uint96 assetPrice
    ) external onlyOrderBook updateSequence {
        require(rawAmount != 0, "A=0"); // Amount Is Zero
        SubAccountId memory decoded = subAccountId.decode();
        require(decoded.account != address(0), "T=0"); // Trader address is zero
        require(_storage.isValidAssetId(decoded.assetId), "LST"); // the asset is not LiSTed
        require(_storage.isValidAssetId(decoded.collateralId), "LST"); // the asset is not LiSTed

        Asset storage asset = _storage.assets[decoded.assetId];
        Asset storage collateral = _storage.assets[decoded.collateralId];
        require(asset.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(collateral.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        assetPrice = LibReferenceOracle.checkPrice(_storage, asset, assetPrice);
        collateralPrice = LibReferenceOracle.checkPrice(_storage, collateral, collateralPrice);

        // fee & funding & borrowing
        uint96 feeUsd = asset.fundingFeeUsd(subAccount, decoded.isLong);
        if (subAccount.size > 0) {
            asset.updateEntryFunding(subAccount, decoded.isLong);
        }
        {
            uint96 feeCollateral = uint256(feeUsd).wdiv(collateralPrice).toUint96();
            require(subAccount.collateral >= feeCollateral, "FEE"); // remaining collateral can not pay FEE
            subAccount.collateral -= feeCollateral;
            _collectFee(decoded.collateralId, decoded.account, feeCollateral);
        }

        // withdraw
        uint96 wadAmount = collateral.toWad(rawAmount);
        require(subAccount.collateral >= wadAmount, "C<W"); // Collateral can not pay fee or is less than the amount requested for Withdrawal
        subAccount.collateral = subAccount.collateral - wadAmount;
        collateral.transferOut(decoded.account, rawAmount);
        require(
            asset.isAccountImSafe(subAccount, decoded.isLong, collateralPrice, assetPrice, _blockTimestamp()),
            "!IM"
        );

        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);

        // trace
        if (subAccount.size == 0 && subAccount.collateral == 0) {
            _storage.userSubAccountIds[decoded.account].remove(subAccountId);
            _storage.subAccountIds.remove(subAccountId);
        }
    }

    function withdrawAllCollateral(bytes32 subAccountId) external onlyOrderBook updateSequence {
        SubAccountId memory decoded = subAccountId.decode();
        SubAccount storage subAccount = _storage.accounts[subAccountId];
        require(subAccount.size == 0, "S>0"); // position Size should be Zero
        require(subAccount.collateral > 0, "C=0"); // Collateral Is Zero

        Asset storage asset = _storage.assets[decoded.assetId];
        Asset storage collateral = _storage.assets[decoded.collateralId];
        require(asset.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        require(collateral.isEnabled(), "ENA"); // the token is temporarily not ENAbled
        uint96 wadAmount = subAccount.collateral;
        uint256 rawAmount = collateral.toRaw(wadAmount);
        subAccount.collateral = 0;
        collateral.transferOut(decoded.account, rawAmount);

        emit WithdrawCollateral(subAccountId, decoded.account, decoded.collateralId, rawAmount, wadAmount);

        // trace
        if (subAccount.size == 0 && subAccount.collateral == 0) {
            _storage.userSubAccountIds[decoded.account].remove(subAccountId);
            _storage.subAccountIds.remove(subAccountId);
        }
    }
}
