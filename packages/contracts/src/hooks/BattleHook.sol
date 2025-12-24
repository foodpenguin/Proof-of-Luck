// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPOLHook} from "../interfaces/IPOLHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "../interfaces/VRFConsumerBaseV2.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";

/**
 * @title BattleHook
 * @notice 大逃殺模式 (Battle Royale) 邏輯 Hook。
 * @dev 包含環狀地圖、縮圈機制與淘汰邏輯。
 */
contract BattleHook is IPOLHook, Ownable, VRFConsumerBaseV2 {
    address public immutable vault;
    
    // VRF 配置
    IVRFCoordinator public vrfCoordinator;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;

    // 遊戲參數
    uint256 public constant MAP_SIZE = 1000;
    uint256 public constant INITIAL_RADIUS = 500;
    uint256 public constant TICKET_PRICE = 100 * 1e6; // 100 USDC
    uint256 public constant PENALTY_BASIS_POINTS = 1000; // 10% (1000/10000)

    struct TicketData {
        uint256 x;
        uint256 y;
        bool isEliminated;
        bool exists;
    }

    mapping(uint256 => TicketData) public ticketInfo;
    uint256[] public activeTickets; // 追蹤所有活躍玩家
    
    uint256 public gameStartTime;
    bool public isGameActive;
    uint256 public declaredWinner;
    address public governance;

    // Zone State
    uint256 public currentCenterX;
    uint256 public currentCenterY;
    uint256 public currentRadius;
    uint8 public pendingAction; // 0=None, 1=Start, 2=Shrink

    event GameStarted(uint256 startTime);
    event ZoneShrunk(uint256 newX, uint256 newY, uint256 newRadius);
    event PlayerEliminated(uint256 indexed tokenId);
    event WinnerDeclared(uint256 indexed tokenId, uint256 prize);
    event GovernanceUpdated(address indexed newGovernance);
    event ShrinkRequested(uint256 requestId);

    constructor(
        address _vault,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subId
    ) Ownable(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        require(_vault != address(0), "Invalid vault");
        vault = _vault;
        vrfCoordinator = IVRFCoordinator(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subId;
        
        // Default center
        currentCenterX = 500;
        currentCenterY = 500;
        currentRadius = INITIAL_RADIUS;
    }

    function setGovernance(address _governance) external onlyOwner {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    /**
     * @notice 啟動遊戲。
     */
    function startGame() external onlyOwner {
        require(!isGameActive, "Game already active");
        require(pendingAction == 0, "Action pending");
        
        isGameActive = true;
        gameStartTime = block.timestamp;
        declaredWinner = 0;
        
        // Request initial random center
        pendingAction = 1; // Start
        _requestRandomness();
        
        emit GameStarted(gameStartTime);
    }

    /**
     * @notice 觸發縮圈。
     */
    function performShrink() external onlyOwner {
        require(isGameActive, "Game not active");
        require(pendingAction == 0, "Action pending");
        require(currentRadius > 0, "Already min radius");
        
        pendingAction = 2; // Shrink
        _requestRandomness();
    }

    function _requestRandomness() internal {
        uint256 requestId = vrfCoordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            2 // Need 2 words for X and Y
        );
        emit ShrinkRequested(requestId);
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        require(pendingAction != 0, "No pending action");
        
        uint256 newX = randomWords[0] % MAP_SIZE;
        uint256 newY = randomWords[1] % MAP_SIZE;
        
        currentCenterX = newX;
        currentCenterY = newY;
        
        if (pendingAction == 1) {
            // Start Game: Reset radius
            currentRadius = INITIAL_RADIUS;
        } else if (pendingAction == 2) {
            // Shrink: Halve radius
            currentRadius = currentRadius / 2;
        }
        
        pendingAction = 0;
        emit ZoneShrunk(currentCenterX, currentCenterY, currentRadius);
    }

    /**
     * @notice 獲取當前安全區半徑。
     */
    function getCurrentRadius() public view returns (uint256) {
        return currentRadius;
    }


    /**
     * @notice 計算兩點在環狀地圖上的距離平方。
     */
    function getDistanceSq(uint256 x1, uint256 y1, uint256 x2, uint256 y2) public pure returns (uint256) {
        uint256 dx = x1 > x2 ? x1 - x2 : x2 - x1;
        uint256 dy = y1 > y2 ? y1 - y2 : y2 - y1;

        if (dx > MAP_SIZE / 2) {
            dx = MAP_SIZE - dx;
        }
        if (dy > MAP_SIZE / 2) {
            dy = MAP_SIZE - dy;
        }

        return dx * dx + dy * dy;
    }

    /**
     * @notice 檢查 Ticket 是否被淘汰。
     */
    function checkElimination(uint256 tokenId) public view returns (bool) {
        if (!ticketInfo[tokenId].exists) return false;
        if (ticketInfo[tokenId].isEliminated) return true;

        uint256 radius = getCurrentRadius();
        uint256 distSq = getDistanceSq(ticketInfo[tokenId].x, ticketInfo[tokenId].y, currentCenterX, currentCenterY);
        
        return distSq > radius * radius;
    }

    /**
     * @notice 判斷贏家。
     * @dev 邏輯:
     * 1. 如果半徑 > 0: 檢查是否只剩 1 人存活。
     * 2. 如果半徑 == 0: 所有人都在圈外，取距離中心最近者。
     * @return winnerTokenId 贏家的 Token ID (若無贏家則為 0)。
     */
    function getWinner() public view returns (uint256 winnerTokenId) {
        if (declaredWinner != 0) return declaredWinner;
        if (!isGameActive) return 0;
        if (activeTickets.length == 0) return 0;

        uint256 radius = getCurrentRadius();

        if (radius > 0) {
            // 模式 1: Last Man Standing
            uint256 survivorCount = 0;
            uint256 lastSurvivor = 0;

            for (uint256 i = 0; i < activeTickets.length; i++) {
                uint256 tid = activeTickets[i];
                if (!checkElimination(tid)) {
                    survivorCount++;
                    lastSurvivor = tid;
                }
            }

            if (survivorCount == 1) {
                return lastSurvivor;
            }
        } else {
            // 模式 2: Sudden Death (Radius == 0)
            // 找出距離中心最近的玩家
            uint256 minDistSq = type(uint256).max;
            uint256 bestCandidate = 0;
            
            for (uint256 i = 0; i < activeTickets.length; i++) {
                uint256 tid = activeTickets[i];
                uint256 distSq = getDistanceSq(ticketInfo[tid].x, ticketInfo[tid].y, currentCenterX, currentCenterY);
                
                if (distSq < minDistSq) {
                    minDistSq = distSq;
                    bestCandidate = tid;
                }
            }
            return bestCandidate;
        }

        return 0; // 遊戲尚未結束
    }

    /**
     * @notice 領取獎金 (僅限贏家)。
     * @dev 這是額外的領獎函式，因為 getRedeemableAmount 是 view 且無法輕易存取 Adapter。
     *      贏家應先呼叫此函式觸發獎金發放，或由 Vault 在 redeem 時觸發。
     *      這裡我們採用 "標記贏家" 的方式，讓 Vault 在 redeem 時知道要全額提款。
     */
    function isWinner(uint256 tokenId) external view returns (bool) {
        return getWinner() == tokenId;
    }

    // --- IPOLHook Implementation ---

    function beforeDeposit(
        address /* caller */,
        uint256 assets,
        uint256 /* shares */,
        bytes calldata data
    ) external view override onlyVault {
        require(assets == TICKET_PRICE, "Invalid ticket price");
        // 如果遊戲已開始，是否允許加入？
        // 假設允許中途加入，但必須在安全區內，否則立即淘汰。
        // 這裡簡單起見，允許加入。
        
        require(data.length == 64, "Invalid data length"); // 2 * 32 bytes (x, y)
        (uint256 x, uint256 y) = abi.decode(data, (uint256, uint256));
        require(x < MAP_SIZE && y < MAP_SIZE, "Coordinates out of bounds");
    }

    function afterDeposit(
        address /* caller */,
        uint256 /* assets */,
        uint256 shares,
        bytes calldata data
    ) external override onlyVault {
        (uint256 x, uint256 y) = abi.decode(data, (uint256, uint256));
        ticketInfo[shares] = TicketData({
            x: x,
            y: y,
            isEliminated: false,
            exists: true
        });
        activeTickets.push(shares);
    }

    function onRedeemRequest(
        address /* caller */,
        uint256 shares,
        bytes calldata /* data */
    ) external override onlyVault {
        // Check if this user is the winner BEFORE removing them
        // If they are the winner, we lock it in so claimRedeem can see it.
        uint256 currentWinner = getWinner();
        if (currentWinner == shares) {
            declaredWinner = shares;
        }

        // 移除 Ticket (Swap and Pop)
        // 尋找並移除 (O(N) cost, but N is limited in Battle Royale usually)
        for (uint256 i = 0; i < activeTickets.length; i++) {
            if (activeTickets[i] == shares) {
                activeTickets[i] = activeTickets[activeTickets.length - 1];
                activeTickets.pop();
                break;
            }
        }
        
        // 注意: 我們不能在這裡 delete ticketInfo[shares]，
        // 因為 claimRedeem 隨後會呼叫 getRedeemableAmount，
        // 而 getRedeemableAmount 需要讀取 ticketInfo 來判斷是否被淘汰。
        // 如果在這裡刪除了，checkElimination 會因為 !exists 返回 false，
        // 導致被誤判為 "倖存者提早退出" (扣罰金)。
    }


    function getRedeemableAmount(
        uint256 tokenId,
        uint256 principal
    ) external view override returns (uint256) {
        // 檢查是否為贏家
        uint256 winnerId = getWinner();
        if (winnerId != 0 && winnerId == tokenId) {
            return principal; 
        }

        bool eliminated = checkElimination(tokenId);
        
        if (eliminated) {
            // 淘汰者取回本金 (利息充公)
            return principal;
        } else {
            // 倖存者提早退出，扣除 10% 罰金
            // 罰金留在 Adapter (即 Protocol Revenue)
            uint256 penalty = (principal * PENALTY_BASIS_POINTS) / 10000;
            return principal - penalty;
        }
    }
}
