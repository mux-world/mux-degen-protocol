// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

library LibTypeCast {
    bytes32 private constant ADDRESS_GUARD_MASK = 0xffffffffffffffffffffffff0000000000000000000000000000000000000000;

    function isAddress(bytes32 v) internal pure returns (bool) {
        return v & ADDRESS_GUARD_MASK == 0;
    }

    function toAddress(bytes32 v) internal pure returns (address) {
        require(v & ADDRESS_GUARD_MASK == 0, "ADR"); // invalid ADdRess
        return address(uint160(uint256(v)));
    }

    function toBytes32(address v) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(v)));
    }

    function toUint32(bytes32 v) internal pure returns (uint32) {
        return toUint32(uint256(v));
    }

    function toUint56(bytes32 v) internal pure returns (uint56) {
        return toUint56(uint256(v));
    }

    function toUint96(bytes32 v) internal pure returns (uint96) {
        return toUint96(uint256(v));
    }

    function toUint256(bytes32 v) internal pure returns (uint256) {
        return uint256(v);
    }

    function toBytes32(uint256 v) internal pure returns (bytes32) {
        return bytes32(v);
    }

    function toBoolean(bytes32 v) internal pure returns (bool) {
        uint256 n = toUint256(v);
        require(n == 0 || n == 1, "O1");
        return n == 1;
    }

    function toBytes32(bool v) internal pure returns (bytes32) {
        return toBytes32(v ? 1 : 0);
    }

    function toUint32(uint256 n) internal pure returns (uint32) {
        require(n <= type(uint32).max, "O32");
        return uint32(n);
    }

    function toUint56(uint256 n) internal pure returns (uint56) {
        require(n <= type(uint56).max, "O56");
        return uint56(n);
    }

    function toUint96(uint256 n) internal pure returns (uint96) {
        require(n <= type(uint96).max, "O96");
        return uint96(n);
    }

    function toUint128(uint256 n) internal pure returns (uint128) {
        require(n <= type(uint128).max, "O12");
        return uint128(n);
    }
}
