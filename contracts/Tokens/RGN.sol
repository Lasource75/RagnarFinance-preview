// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/interface.sol";

/// @title Rgn
/// @author Ragnar Team
contract RGN is MintableERC20 {
    using SafeERC20 for IERC20;
    uint256 public constant MAX_SUPPLY = 100 * 10**6 * 1 ether;
    mapping(address => bool) minters;
    address public previousRGN;
    address public previousLRGN;
    uint256 public maxSupplyUpdated = 100 * 10**6 * 1 ether;
    uint256 public amountConverted;

    constructor(
        string memory _name,
        string memory _symbol,
        uint256 _initialMint,
        address _initialMintTo
    ) MintableERC20(_name, _symbol) {
        _mint(_initialMintTo, _initialMint);
    }

    modifier onlyMinters(){
        require(minters[msg.sender], "Not a minter");
        _;
    }

    function setPreviousRGN(address _previousRGN) external onlyOwner {
        require(previousRGN == address(0), "bad address");
        previousRGN = _previousRGN;
    }

    function updateMaxSupply() external onlyOwner {
        maxSupplyUpdated =
            MAX_SUPPLY -
            IERC20(previousRGN).totalSupply() +
            IERC20(previousLRGN).totalSupply();
    }

    function setPreviousLRGN(address _previousLRGN) external onlyOwner {
        require(previousLRGN == address(0), "bad address");
        previousLRGN = _previousLRGN;
    }

    modifier onlyMinter() {
        require(minters[msg.sender], "Only Minter");
        _;
    }

    // RGN is owned by the Masterchief of the protocol, forbidding misuse of this function
    function mint(address _to, uint256 _amount) public override onlyMinters {
        // TODO : For mainnet
        /*
        if (totalSupply() + _amount > maxSupplyUpdated + amountConverted) {
            _amount = maxSupplyUpdated + amountConverted - totalSupply();
        }
        */
        _mint(_to, _amount * 10**18);
    }

    function burn(address _from, uint256 _amount) public override onlyMinters {
        _burn(_from, _amount);
    }


    function deposit(uint256 _amount) external {
        require((previousRGN != address(0)), "Previous RGN not set");
        if (totalSupply() + _amount > MAX_SUPPLY) {
            _amount = MAX_SUPPLY - totalSupply();
        }
        IERC20(previousRGN).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        _mint(msg.sender, _amount);
        amountConverted += _amount;
    }

    function addMinter(address _minter) external onlyOwner {
        minters[_minter] = true;
    }

    function removeMinter(address _minter) external onlyOwner {
        minters[_minter] = false;
    }
}
