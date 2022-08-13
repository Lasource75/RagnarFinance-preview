// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Authorizable is Ownable{

    mapping(address => bool) authorized;

    function addToAuthorized(address _newAuthorized) external onlyOwner {
        authorized[_newAuthorized] = true;
    }

    function removeFromAuthorized(address _oldAuthorized) external onlyOwner {
        authorized[_oldAuthorized] = false;
    }

}