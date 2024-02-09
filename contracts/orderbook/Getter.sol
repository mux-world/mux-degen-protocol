// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";

import "./Types.sol";
import "./Storage.sol";

contract Getter is Storage {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function nextOrderId() external view returns (uint64) {
        return _storage.nextOrderId;
    }

    function getParameter(bytes32 key) external view returns (bytes32) {
        return _storage.parameters[key];
    }

    /**
     * @notice Get an Order by orderId.
     */
    function getOrder(uint64 orderId) external view returns (OrderData memory, bool) {
        return (_storage.orderData[orderId], _storage.orderData[orderId].version > 0);
    }

    function getOrders(
        uint256 begin,
        uint256 end
    ) external view returns (OrderData[] memory orderDataArray, uint256 totalCount) {
        totalCount = _storage.orders.length();
        if (begin >= end || begin >= totalCount) {
            return (orderDataArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        orderDataArray = new OrderData[](size);
        for (uint256 i = 0; i < size; i++) {
            uint64 orderId = uint64(_storage.orders.at(i + begin));
            orderDataArray[i] = _storage.orderData[orderId];
        }
    }

    function getOrdersOf(
        address user,
        uint256 begin,
        uint256 end
    ) external view returns (OrderData[] memory orderDataArray, uint256 totalCount) {
        EnumerableSetUpgradeable.UintSet storage orders = _storage.userOrders[user];
        totalCount = orders.length();
        if (begin >= end || begin >= totalCount) {
            return (orderDataArray, totalCount);
        }
        end = end <= totalCount ? end : totalCount;
        uint256 size = end - begin;
        orderDataArray = new OrderData[](size);
        for (uint256 i = 0; i < size; i++) {
            uint64 orderId = uint64(orders.at(i + begin));
            orderDataArray[i] = _storage.orderData[orderId];
        }
    }
}
