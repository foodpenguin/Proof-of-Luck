// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ITicketDescriptor} from "./interfaces/ITicketDescriptor.sol";

contract TicketDescriptor is ITicketDescriptor, Ownable {
    using Strings for uint256;

    constructor() Ownable(msg.sender) {}

    function render(uint256 tokenId, uint256 assets, bool isDead, uint16 x, uint16 y) public pure returns (string memory) {
        string memory color = isDead ? "gray" : "green";
        string memory xStr = uint256(x).toString();
        string memory yStr = uint256(y).toString();
        string memory assetsStr = assets.toString();

        return string(abi.encodePacked(
            '<svg xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350">',
            '<style>.base { fill: white; font-family: serif; font-size: 14px; }</style>',
            '<rect width="100%" height="100%" fill="black" />',
            '<circle cx="', xStr, '" cy="', yStr, '" r="10" fill="', color, '" />',
            '<text x="50%" y="40%" class="base" dominant-baseline="middle" text-anchor="middle">',
            'Ticket #', tokenId.toString(),
            '</text>',
            '<text x="50%" y="50%" class="base" dominant-baseline="middle" text-anchor="middle">',
            'Assets: ', assetsStr,
            '</text>',
            '<text x="50%" y="60%" class="base" dominant-baseline="middle" text-anchor="middle">',
            'Pos: (', xStr, ', ', yStr, ')',
            '</text>',
            '</svg>'
        ));
    }

    function tokenURI(uint256 tokenId, uint256 assets, uint8 mode, bool isDead, uint16 x, uint16 y) external pure override returns (string memory) {
        string memory svg = render(tokenId, assets, isDead, x, y);
        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name": "POL Ticket #', tokenId.toString(), '",',
            '"description": "Proof of Luck Ticket",',
            '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
            '"attributes": [',
            '{"trait_type": "Assets", "value": ', assets.toString(), '},',
            '{"trait_type": "Mode", "value": ', uint256(mode).toString(), '}',
            ']}'
        ))));

        return string(abi.encodePacked("data:application/json;base64,", json));
    }
}