// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "../MainProtocol/interfaces/IYetiBooster.sol";

/// @title rgnYETI
/// @author Ragnar Team
/// @notice rgnYETI is a token minted when 1 yeti is staked in the ragnar protocol
contract RGNYETI is ERC20 {
    using SafeERC20 for IERC20;
    address public immutable mainContract;
    address public immutable yeti;

    event RgnYetiMinted(address indexed user, uint256 amount);

    constructor(address _mainContract, address _yeti) ERC20("rgnYETI", "rgnYETI") {
        mainContract = _mainContract;
        yeti = _yeti;
    }

    /// @notice deposit YETI in Ragnar protocol and get rgnYETI at a 1:1 rate
    /// @param _amount the amount of JOE
    function deposit(uint256 _amount) external {
        IERC20(yeti).safeTransferFrom(msg.sender, mainContract, _amount);
        IYetiBooster(mainContract).stakeYETI(_amount);
        _mint(msg.sender, _amount);
        emit RgnYetiMinted(msg.sender, _amount);
    }
}
