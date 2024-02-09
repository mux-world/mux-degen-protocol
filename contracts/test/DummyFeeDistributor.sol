// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "../interfaces/IDistributor.sol";

contract DummyFeeDistributor is IDistributor {
    function updateRewards(uint8 tokenId, address tokenAddress, address trader, uint96 rawAmount) external pure {
        tokenId;
        tokenAddress;
        trader;
        rawAmount;
    }
}
