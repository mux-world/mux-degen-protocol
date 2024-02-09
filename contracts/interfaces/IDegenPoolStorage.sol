// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

interface IDegenPoolStorage {
    event UpdateSequence(uint256 sequence);
    event CollectedFee(uint8 tokenId, uint96 wadFeeCollateral);
}
