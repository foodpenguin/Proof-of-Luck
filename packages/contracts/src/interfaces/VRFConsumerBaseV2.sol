// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VRFConsumerBaseV2
 * @notice 簡化的 VRF Consumer Base，用於接收隨機數。
 */
abstract contract VRFConsumerBaseV2 {
    error OnlyCoordinatorCanFulfill(address have, address want);
    address private immutable vrfCoordinator;

    constructor(address _vrfCoordinator) {
        vrfCoordinator = _vrfCoordinator;
    }

    /**
     * @notice 接收隨機數的回調函式。
     * @param requestId 請求 ID。
     * @param randomWords 隨機數陣列。
     */
    function rawFulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        if (msg.sender != vrfCoordinator) {
            revert OnlyCoordinatorCanFulfill(msg.sender, vrfCoordinator);
        }
        fulfillRandomWords(requestId, randomWords);
    }

    /**
     * @notice 子合約需實作此函式以處理隨機數。
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal virtual;
}
