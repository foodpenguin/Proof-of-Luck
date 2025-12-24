// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPOLHook} from "../interfaces/IPOLHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "../interfaces/VRFConsumerBaseV2.sol";
import {MasterVault} from "../MasterVault.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";

/**
 * @title GeneralHook
 * @notice Proof of Luck 的一般池邏輯 (Savings Pool)。
 * @dev 負責每日開獎邏輯與 NFT 權重進化。
 */
contract GeneralHook is IPOLHook, Ownable, VRFConsumerBaseV2 {
    address public vault;

    // VRF 配置
    IVRFCoordinator public vrfCoordinator;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;

    // 彩票狀態
    uint256 public lastDrawTimestamp;
    uint256 public drawInterval = 1 days;
    uint256 public currentDrawId;
    bool public isDrawPending;

    // 參與者
    // 簡單實作：將所有 TokenID 存入陣列。生產環境可能需要更高效的結構 (如 Merkle Tree 或 Snapshot)。
    uint256[] public activeTickets;
    mapping(uint256 => uint256) public ticketIndex; // TokenID -> Index in activeTickets
    mapping(uint256 => bool) public isTicketActive;

    // NFT 進化（權重）
    mapping(uint256 => uint256) public nftWeight; // TokenID -> Weight (Base 100)

    event DrawRequested(uint256 indexed drawId, uint256 requestId);
    event DrawCompleted(uint256 indexed drawId, uint256 winnerTokenId, uint256 randomWord);
    event TicketEvolved(uint256 indexed tokenId, uint256 newWeight);

    constructor(
        address _vault,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subId
    ) Ownable(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        vault = _vault;
        vrfCoordinator = IVRFCoordinator(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subId;
        lastDrawTimestamp = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    /**
     * @notice 存款前檢查。
     */
    function beforeDeposit(
        address /* caller */,
        uint256 /* assets */,
        uint256 /* shares */,
        bytes calldata /* data */
    ) external view override onlyVault {
        require(!isDrawPending, "Draw in progress");
    }

    /**
     * @notice 存款後邏輯。
     * @dev 記錄參與者。
     */
    function afterDeposit(
        address /* caller */,
        uint256 /* assets */,
        uint256 shares,
        bytes calldata /* data */
    ) external override onlyVault {
        uint256 tokenId = shares;
        activeTickets.push(tokenId);
        ticketIndex[tokenId] = activeTickets.length - 1;
        isTicketActive[tokenId] = true;
        nftWeight[tokenId] = 100; // 初始權重 100
    }

    /**
     * @notice 贖回請求邏輯。
     */
    function onRedeemRequest(
        address /* caller */,
        uint256 shares,
        bytes calldata /* data */
    ) external override onlyVault {
        require(!isDrawPending, "Draw in progress");
        
        uint256 tokenId = shares;
        require(isTicketActive[tokenId], "Ticket not active");

        // 移除 Ticket (Swap and Pop)
        uint256 index = ticketIndex[tokenId];
        uint256 lastTokenId = activeTickets[activeTickets.length - 1];

        activeTickets[index] = lastTokenId;
        ticketIndex[lastTokenId] = index;
        activeTickets.pop();

        delete ticketIndex[tokenId];
        delete isTicketActive[tokenId];
        delete nftWeight[tokenId];
    }

    /**
     * @notice 計算贖回金額。
     * @dev General Pool 為無損彩票，始終返回本金。
     */
    function getRedeemableAmount(
        uint256 /* tokenId */,
        uint256 principal
    ) external pure override returns (uint256) {
        return principal;
    }

    /**
     * @notice 觸發每日開獎 (任何人可呼叫，或由 Keeper 觸發)。
     */
    function performDraw() external {
        require(!isDrawPending, "Draw already pending");
        require(block.timestamp >= lastDrawTimestamp + drawInterval, "Too early");
        require(activeTickets.length > 0, "No participants");

        isDrawPending = true;
        currentDrawId++;

        uint256 requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            1 // numWords
        );

        emit DrawRequested(currentDrawId, requestId);
    }

    /**
     * @notice VRF 回調，決定贏家並進化 NFT。
     */
    function fulfillRandomWords(uint256 /* requestId */, uint256[] memory randomWords) internal override {
        require(isDrawPending, "No pending draw");
        isDrawPending = false;
        
        uint256 randomWord = randomWords[0];
        
        // 1. Calculate Total Weighted Balance
        uint256 totalWeighted = 0;
        uint256[] memory weights = new uint256[](activeTickets.length);
        
        for (uint256 i = 0; i < activeTickets.length; i++) {
            uint256 tid = activeTickets[i];
            (uint128 assets, , , , , , , ) = MasterVault(vault).tickets(tid);
            uint256 principal = uint256(assets);
            // Weight is base 100. 100 = 1x. 105 = 1.05x.
            // Effective = Principal * Weight / 100.
            // To avoid division, we sum Principal * Weight.
            uint256 w = nftWeight[tid];
            if (w == 0) w = 100; // Default
            
            uint256 effective = principal * w;
            weights[i] = effective;
            totalWeighted += effective;
        }
        
        if (totalWeighted == 0) {
            lastDrawTimestamp = block.timestamp;
            return;
        }
        
        // 2. Pick Winner
        uint256 winnerVal = randomWord % totalWeighted;
        uint256 currentSum = 0;
        uint256 winnerId = 0;
        
        for (uint256 i = 0; i < activeTickets.length; i++) {
            currentSum += weights[i];
            if (winnerVal < currentSum) {
                winnerId = activeTickets[i];
                break;
            }
        }
        
        // 3. Distribute Prize
        if (winnerId != 0) {
            MasterVault(vault).distributeYieldToTicket(winnerId);
            nftWeight[winnerId] = 100; // Reset weight
            emit DrawCompleted(currentDrawId, winnerId, randomWord);
        }
        
        // 4. Increase Weight for 1%
        // Use randomWord hash to pick
        uint256 count = activeTickets.length / 100;
        if (count == 0 && activeTickets.length > 0) count = 1; // At least 1
        
        for (uint256 i = 0; i < count; i++) {
            // Simple pseudo-random selection
            uint256 idx = uint256(keccak256(abi.encode(randomWord, i))) % activeTickets.length;
            uint256 tid = activeTickets[idx];
            if (tid != winnerId) {
                nftWeight[tid] += 5; // +0.05 (Base 100)
                emit TicketEvolved(tid, nftWeight[tid]);
            }
        }
        
        lastDrawTimestamp = block.timestamp;
    }
}
