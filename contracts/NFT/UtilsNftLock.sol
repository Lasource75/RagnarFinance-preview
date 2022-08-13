pragma solidity ^0.8.0;

import "./imports/RoyaltiesImpl.sol";
import "./imports/LibPart.sol";
import "./imports/LibRoyalties.sol";

import "./RgnLock.sol";


contract UtilsNftLock is RoyaltiesImpl {

    // Royalties address for resale tax on marketplaces
    address public royaltiesAddress;

    address public rgnLock;

    address payable royaltiesAddressPayable;

    constructor() public {
    }

    function setRgnLock(address _rgnLock) public {
        require(msg.sender == address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266), "Error not address owner");
        rgnLock = _rgnLock;
    }

    function setRoyaltiesAddress(address _addr) public {
        require(msg.sender == rgnLock, "Error not address rgnLock");
        royaltiesAddressPayable = payable(_addr);
    }

    function uint2str(uint _i) external pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    string internal constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

    function base64(bytes memory data) external pure returns (string memory) {
        if (data.length == 0) return '';

        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
        // set the actual output length
            mstore(result, encodedLen)

        // prepare the lookup table
            let tablePtr := add(table, 1)

        // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

        // result ptr, jump over length
            let resultPtr := add(result, 32)

        // run over the input, 3 bytes at a time
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)

            // read 3 bytes
                let input := mload(dataPtr)

            // write 4 characters
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }

        // padding with '='
            switch mod(mload(data), 3)
            case 1 {mstore(sub(resultPtr, 2), shl(240, 0x3d3d))}
            case 2 {mstore(sub(resultPtr, 1), shl(248, 0x3d))}
        }
        return result;
    }

    function setRoyalties(uint tokenId, uint96 percentageBasisPoints)
    external
    {
        require(msg.sender == rgnLock, "Error not address rgnLock");
        LibPart.Part[] memory royalties = new LibPart.Part[](1);
        royalties[0].value = percentageBasisPoints;
        royalties[0].account = royaltiesAddressPayable;
        _saveRoyalties(tokenId, royalties);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[_tokenId];
        if (_royalties.length > 0) {
            return (_royalties[0].account, (_salePrice * _royalties[0].value) / 10000);
        }
    }
}
