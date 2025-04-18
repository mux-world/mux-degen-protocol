// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

// first introduced in mux-staking
interface IReferralManager {
    struct TierSetting {
        uint8 tier;
        uint64 stakeThreshold;
        uint64 discountRate; // 1e5. ex: 2500 = 2.5%
        uint64 rebateRate; // 1e5. ex: 2500 = 2.5%
    }

    event RegisterReferralCode(address referralCodeOwner, bytes32 referralCode);
    event SetReferralCode(address trader, bytes32 referralCode);
    event SetHandler(address handler, bool enable);
    event SetTiers(TierSetting[] newTierSettings);
    event SetMaintainer(address previousMaintainer, address newMaintainer);
    event SetRebateRecipient(bytes32 referralCode, address referralCodeOwner, address rebateRecipient);
    event TransferReferralCode(bytes32 referralCode, address previousOwner, address newOwner);

    function isHandler(address handler) external view returns (bool);

    function rebateRecipients(bytes32 referralCode) external view returns (address);

    // management methods
    function setHandler(address handler, bool enable) external;

    function setTiers(TierSetting[] memory newTierSettings) external;

    // methods only available on primary network
    function isValidReferralCode(bytes32 referralCode) external view returns (bool);

    function registerReferralCode(bytes32 referralCode, address rebateRecipient) external;

    function setRebateRecipient(bytes32 referralCode, address rebateRecipient) external;

    function transferReferralCode(bytes32 referralCode, address newOwner) external;

    // methods available on secondary network
    function getReferralCodeOf(address trader) external view returns (bytes32, uint256);

    function setReferrerCode(bytes32 referralCode) external;

    function setReferrerCodeFor(address trader, bytes32 referralCode) external;

    function tierSettings(
        uint256 tier
    ) external view returns (uint8 retTier, uint64 stakeThreshold, uint64 discountRate, uint64 rebateRate);
}
