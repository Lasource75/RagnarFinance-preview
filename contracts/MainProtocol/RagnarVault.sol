// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @notice RagnarVault is a simple contract used on testnet only to allow users to mint RGN and YETI tokens.

contract RagnarVault is Ownable {
    address yetiAddress;
    address rgnAddress;
    uint256 mintLimit;


    mapping(address => bool) authorized;
/*
    constructor() {
        authorized[msg.sender] = true;
    }
*/
    function addAuthorized(address _authorized) external onlyOwner {
        authorized[_authorized] = true;
    }

    function removeAuthorized(address _authorized) external onlyOwner {
        authorized[_authorized] = false;
    }

    modifier onlyAuthorized(){
        require(authorized[msg.sender], "Your not authorized");
        _;
    }

    function setYeti(address _addressToSet) external onlyAuthorized {
        yetiAddress = _addressToSet;
    }

    function setRgn(address _addressToSet) external onlyAuthorized {
        rgnAddress = _addressToSet;
    }

    /**
     * @dev The _amount parameter is assumed to not be in wei ! 
     */
    function setLimit(uint256 _amount) external onlyAuthorized {
        mintLimit = _amount;
    }

    function mintYeti(uint256 _amount) external {
        require(IERC20(yetiAddress).balanceOf(address(this)) >= _amount,"Insufficient tokens available.");
        require(IERC20(yetiAddress).balanceOf(msg.sender) <= mintLimit * 10 ** 18, "You own too much YETI.");
        IERC20(yetiAddress).transfer(msg.sender, _amount);
    }

    function mintRgn(uint256 _amount) external {
        require(IERC20(rgnAddress).balanceOf(address(this)) >= _amount,"Insufficient tokens available.");
        require(IERC20(rgnAddress).balanceOf(msg.sender) <= mintLimit * 10 ** 18, "You own too much RGN.");
        IERC20(rgnAddress).transfer(msg.sender, _amount);
    }

}
