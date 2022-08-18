// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BRGN is ERC20, Ownable{


    constructor() ERC20("BRGN", "BRGN") {
    }

    mapping(address => bool) minters;

    function mint(address to, uint256 amount) public onlyMinters {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public onlyMinters {
        _burn(from, amount);
    }

    function approve( address owner,address spender,uint256 amount) public
    {
        _approve(owner,spender,amount);
    }

    modifier onlyMinters(){
        require(minters[msg.sender], "Not a minter");
        _;
    }
    
    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
    }
}
