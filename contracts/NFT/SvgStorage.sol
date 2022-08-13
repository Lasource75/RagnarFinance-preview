// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./RgnLock.sol";

contract storageSVG is Ownable {

    // Piece of svg
    mapping (uint=>string ) public paths;

    // The Utils nft lock
    RGNLOCK rgnLock;

    constructor() {
    }

    function tokenURI(bool exists, uint256 RgnLock, uint256 timeToLock, uint256 BRgnLock, uint8 monthLock, uint256 id)
    public
    view
    returns (string memory)
    {
        require(exists, "ERC721Metadata: URI query for nonexistent token");
        string memory linkImage = returnSVG(RgnLock, timeToLock, 50, BRgnLock, monthLock);
        string memory attributes = string(abi.encodePacked("\"attributes\":[{\"trait_type\":\"RGN locked","\",\"value\":\"",uint2str(RgnLock),"\"},{\"trait_type\":\"BRGN locked","\",\"value\":\"",uint2str(BRgnLock),"\"}]"));
    string memory json = base64(
            bytes(string(
            abi.encodePacked(
                '{',
                '"name": "RGN lock ', uint2str(id) , '"',
                ', "edition":"', uint2str(id), '"',
                ', "image":"', linkImage,'"',
                ',',attributes,
                '}'
                )
            ))
        );
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function returnSVG (uint amountRgn, uint time, uint apr, uint bRgn, uint8 month) public view returns (string memory) {
        string memory baseURL = "data:image/svg+xml;base64,";
        string memory content = string(abi.encodePacked(paths[0], getColor(month),paths[1], getColorText(month), paths[2], uint2str(time), paths[3], uint2str(amountRgn)));
        string memory finalSVG  = string(abi.encodePacked(content, paths[4], uint2str(bRgn), paths[5], getLibMonth(month), paths[6], "coming soon", paths[7], paths[8]));
        string memory svgBase64Encoded = base64(bytes(string(abi.encodePacked(finalSVG))));
        return string(abi.encodePacked(baseURL,svgBase64Encoded));
    }

    /// @notice Add piece of svg only use by owner
    /// @param pid placing into mapping for stocking string
    /// @param draw field containing a piece of the svg file
    function addData(uint pid, string memory draw)
    public onlyOwner
    {
        paths[pid] = draw;
    }

    function setRgnLock(RGNLOCK _rgnLock) public onlyOwner {
        rgnLock = _rgnLock;
    }

    // @notice return string month from into month
    // @param _month month for lock nft
    function getLibMonth(uint8 _month)
    private
    pure
    returns (string memory name)
    {
        if (_month == 3)
            return "3 months";
        if (_month == 6)
            return "6 months";
        if (_month == 12)
            return "12 months";
        if (_month == 18)
            return "18 months";
        else
            return "1 months";
    }

    // @notice return string color from into month
    // @param _month month for lock nft
    function getColor(uint8 _month)
    private
    pure
    returns (string memory color)
    {
        if (_month == 3)
            return "#DE7650";
        if (_month == 6)
            return "#6D859C";
        if (_month == 12)
            return "#506B7E";
        if (_month == 18)
            return "#23272C";
        else
            return "#6B6857";
    }

    // @notice return string color text from into month
    // @param _month month for lock nft
    function getColorText(uint8 _month)
    private
    view
    returns (string memory color)
    {
        if (_month == 18)
            return "#DE7650";
        else
            return "#2D3239";
    }

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
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

    function base64(bytes memory data) internal pure returns (string memory) {
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
}
