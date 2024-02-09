// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "../interfaces/IReferralTiers.sol";

contract ReferralTiers is AccessControlEnumerableUpgradeable, IReferralTiers {
    bytes32 constant MAINTAINER_ROLE = keccak256("MAINTAINER_ROLE");

    event SetTier(bytes32 indexed code, uint256 tier);

    mapping(bytes32 => uint256) public code2Tier;

    function initialize() external initializer {
        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _grantRole(MAINTAINER_ROLE, _msgSender());
    }

    function setTier(bytes32[] memory codes, uint256[] memory tiers) external onlyRole(MAINTAINER_ROLE) {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender) || hasRole(MAINTAINER_ROLE, msg.sender), "ADM"); // ADMin or maintainer
        require(codes.length == tiers.length, "LEN"); // LENgth mismatch
        for (uint256 i = 0; i < codes.length; i++) {
            code2Tier[codes[i]] = tiers[i];
            emit SetTier(codes[i], tiers[i]);
        }
    }

    function getTiers(bytes32[] memory codes) external view returns (uint256[] memory) {
        uint256[] memory tiers = new uint256[](codes.length);
        for (uint256 i = 0; i < codes.length; i++) {
            tiers[i] = code2Tier[codes[i]];
        }
        return tiers;
    }
}
