// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

interface IReferralTiers {
    function code2Tier(bytes32 code) external returns (uint256);
}
