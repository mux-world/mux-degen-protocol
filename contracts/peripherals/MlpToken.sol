// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MlpToken is Initializable, ERC20Upgradeable {
    address public liquidityPool;

    function initialize(string memory name_, string memory symbol_, address liquidityPool_) external initializer {
        __ERC20_init(name_, symbol_);
        liquidityPool = liquidityPool_;
    }

    function mint(address to, uint256 amount) public {
        require(_msgSender() == liquidityPool, "MUXLP: role");
        _mint(to, amount);
    }

    function burn(address account, uint256 amount) public {
        require(_msgSender() == liquidityPool, "MUXLP: role");
        _burn(account, amount);
    }
}
