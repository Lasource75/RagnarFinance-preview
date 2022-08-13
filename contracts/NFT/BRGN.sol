// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract BRGN is ERC20 {


    constructor() ERC20("BRGN", "BRGN") {
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function approve( address owner,address spender,uint256 amount) public
    {
        _approve(owner,spender,amount);
    }
}
