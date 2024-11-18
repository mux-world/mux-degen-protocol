// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "../third-party/Diamond.sol";
import "../interfaces/IDegenPool.sol";
import "../interfaces/IOrderBook.sol";
import "../libraries/LibConfigKeys.sol";
import "../libraries/LibTypeCast.sol";

/**
 * @notice DegenPOL saves Protocol-Owned-Liquidity.
 */
contract DegenPOL is Initializable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using LibTypeCast for bytes32;

    event TransferETH(address indexed to, uint256 amount);
    event TransferERC20Token(address indexed token, address indexed to, uint256 amount);
    event SetMaintainer(address newMaintainer, bool enable);

    IDegenPool public degenPool;
    IOrderBook public orderBook;
    mapping(address => bool) public maintainers;

    function initialize(IDegenPool degenPool_, IOrderBook orderBook_) external initializer {
        __Ownable_init();
        degenPool = degenPool_;
        orderBook = orderBook_;

        // adding ERC165 data
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true;
    }

    function setMaintainer(address newMaintainer, bool enable) external onlyOwner {
        maintainers[newMaintainer] = enable;
        emit SetMaintainer(newMaintainer, enable);
    }

    /**
     * @notice  A helper method to transfer Ether to somewhere.
     *
     * @param   recipient   The receiver of the sent asset.
     * @param   value       The amount of asset to send.
     */
    function transferETH(address recipient, uint256 value) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        require(recipient != address(0), "recipient is zero address");
        require(value != 0, "transfer value is zero");
        AddressUpgradeable.sendValue(payable(recipient), value);
        emit TransferETH(recipient, value);
    }

    /**
     * @notice  A helper method to transfer ERC20 to somewhere.
     *
     * @param   recipient   The receiver of the sent asset.
     * @param   tokens      The address of to be sent ERC20 token.
     * @param   amounts     The amount of asset to send.
     */
    function transferERC20(address recipient, address[] memory tokens, uint256[] memory amounts) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        require(recipient != address(0), "recipient is zero address");
        require(tokens.length == amounts.length, "length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Upgradeable(tokens[i]).safeTransfer(recipient, amounts[i]);
            emit TransferERC20Token(tokens[i], recipient, amounts[i]);
        }
    }

    function cancelOrder(uint64 orderId) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        orderBook.cancelOrder(orderId);
    }

    /**
     * @dev Buy/sell MlpToken.
     *
     *      Send the token to this DegenPOL before calling this method.
     */
    function placeLiquidityOrder(
        uint8 assetId,
        uint96 rawAmount, // erc20.decimals. collateral token if adding, mlp token if removing
        bool isAdding
    ) external {
        require(msg.sender == owner() || maintainers[msg.sender], "must be maintainer or owner");
        address tokenAddress;
        if (isAdding) {
            tokenAddress = degenPool.getAssetParameter(assetId, LibConfigKeys.TOKEN_ADDRESS).toAddress();
        } else {
            tokenAddress = degenPool.getPoolParameter(LibConfigKeys.MLP_TOKEN).toAddress();
        }
        IERC20Upgradeable(tokenAddress).approve(address(orderBook), rawAmount);
        orderBook.placeLiquidityOrder(
            LiquidityOrderParams({ assetId: assetId, rawAmount: rawAmount, isAdding: isAdding })
        );
    }

    bytes32[49] private __gap;
}
