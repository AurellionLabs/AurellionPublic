// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Mock is ERC20 {
    uint8 private immutable _mockDecimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _mockDecimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _mockDecimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
