// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title VRFCoordinatorMock
 * @notice 模擬 Chainlink VRF Coordinator V2。
 * @dev 用於本地測試隨機數請求與回應。
 */
contract VRFCoordinatorMock {
    event RandomWordsRequested(
        bytes32 indexed keyHash,
        uint256 requestId,
        uint256 preSeed,
        uint64 indexed subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        address indexed sender
    );

    event RandomWordsFulfilled(uint256 requestId, uint256 outputSeed, uint96 payment, bool success);

    uint256 public nextRequestId = 1;
    mapping(uint256 => address) public requestConsumers;
    mapping(uint256 => uint32) public requestNumWords;

    /**
     * @notice 請求隨機數。
     * @return requestId 請求 ID。
     */
    function requestRandomWords(
        bytes32 keyHash,
        uint64 subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords
    ) external returns (uint256 requestId) {
        requestId = nextRequestId++;
        requestConsumers[requestId] = msg.sender;
        requestNumWords[requestId] = numWords;

        emit RandomWordsRequested(
            keyHash,
            requestId,
            uint256(keccak256(abi.encode(requestId, block.timestamp))),
            subId,
            minimumRequestConfirmations,
            callbackGasLimit,
            numWords,
            msg.sender
        );

        return requestId;
    }

    /**
     * @notice 履行隨機數請求 (模擬 Chainlink 節點回調)。
     * @param requestId 要履行的請求 ID。
     * @param randomWords 隨機數陣列。
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        address consumer = requestConsumers[requestId];
        require(consumer != address(0), "Invalid request");
        require(randomWords.length == requestNumWords[requestId], "Invalid random words length");

        // 呼叫 Consumer 的 rawFulfillRandomWords
        // 注意: 這裡假設 Consumer 繼承自 VRFConsumerBaseV2，其實作了 rawFulfillRandomWords
        (bool success, ) = consumer.call(
            abi.encodeWithSignature("rawFulfillRandomWords(uint256,uint256[])", requestId, randomWords)
        );
        
        require(success, "Callback failed");
        emit RandomWordsFulfilled(requestId, 0, 0, success);
        
        delete requestConsumers[requestId];
        delete requestNumWords[requestId];
    }
}
