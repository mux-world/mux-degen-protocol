// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./IDegenPoolStorage.sol";
import "./IAccount.sol";
import "./IAdmin.sol";
import "./IGetter.sol";
import "./ILiquidity.sol";
import "./ITrade.sol";

import "../Types.sol";

interface IDegenPool is IDegenPoolStorage, IAccount, IAdmin, IGetter, ILiquidity, ITrade {}
