// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface ITicketDescriptor {
    function tokenURI(
        uint256 tokenId, 
        uint256 assets, 
        uint8 mode, 
        bool isDead, 
        uint16 x, 
        uint16 y
    ) external view returns (string memory);
}