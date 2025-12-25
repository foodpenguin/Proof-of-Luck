// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPOLHook} from "../interfaces/IPOLHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "../interfaces/VRFConsumerBaseV2.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";

/**
 * @title BattleHook
 * @notice Battle Royale Logic Hook (Round-Based) with Join/Battle Phases.
 */
contract BattleHook is IPOLHook, Ownable, VRFConsumerBaseV2 {
    address public immutable vault;
    
    // VRF Config
    IVRFCoordinator public vrfCoordinator;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 2500000; // Increased gas limit for complex logic
    uint16 public requestConfirmations = 3;

    // Game Constants
    uint256 public constant MAP_SIZE = 1000;
    uint256 public constant INITIAL_RADIUS = 500;
    uint256 public constant TICKET_PRICE = 100 * 1e6; // 100 USDC
    uint256 public constant PENALTY_BASIS_POINTS = 1000; // 10% penalty for early exit
    
    // (2) 報名時間與縮圈間隔設定
    uint256 public constant JOIN_DURATION = 1 days; 
    uint256 public constant SHRINK_INTERVAL = 1 days;

    // 遊戲狀態機
    enum GameState {
        Inactive, // 0: 回合尚未開始或已結束
        Joining,  // 1: 開放報名中，等待正式開戰
        Battling  // 2: 戰鬥進行中，已鎖定參賽者，新加入者排隊至下一輪
    }

    struct RoundInfo {
        uint256 startTime;      // startNewRound 的時間
        uint256 joinDeadline;   // 報名截止時間 (預計開始戰鬥時間)
        uint256 lastActionTime; // 上一次縮圈或開始的時間
        uint256 currentCenterX;
        uint256 currentCenterY;
        uint256 currentRadius;
        GameState state;        // 當前狀態
        uint256 winnerId;
    }

    struct TicketData {
        uint256 x;
        uint256 y;
        bool isEliminated;
        bool exists;
        uint256 roundId; // 這張票屬於哪一回合
    }

    // State
    uint256 public currentRoundId;
    mapping(uint256 => RoundInfo) public rounds;
    mapping(uint256 => TicketData) public ticketInfo;
    mapping(uint256 => uint256[]) public roundTickets; // roundId => ticketIds

    // VRF State: 0=None, 1=StartGame(InitCenter), 2=Shrink
    uint8 public pendingAction; 
    
    // Events
    event GameRoundOpened(uint256 indexed roundId, uint256 joinDeadline);
    event GameBattlingStarted(uint256 indexed roundId, uint256 startCenterX, uint256 startCenterY);
    event ZoneShrunk(uint256 indexed roundId, uint256 newX, uint256 newY, uint256 newRadius);
    event PlayerEliminated(uint256 indexed roundId, uint256 indexed tokenId);
    event WinnerDeclared(uint256 indexed roundId, uint256 indexed tokenId, uint256 prize);
    event GovernanceUpdated(address indexed newGovernance);
    event ShrinkRequested(uint256 requestId);

    address public governance;

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
        
        currentRoundId = 0;
    }

    function setGovernance(address _governance) external onlyOwner {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    // --- Game Lifecycle ---

    /**
     * @notice (1) 開始新回合：進入 Joining 狀態
     * @dev 設定報名截止時間，等待玩家存款。
     */
    function startNewRound() external onlyOwner {
        // 只有當前回合結束或未開始時才能開啟新回合
        require(rounds[currentRoundId].state == GameState.Inactive || rounds[currentRoundId].winnerId != 0, "Current round active");
        require(pendingAction == 0, "Action pending");
        
        currentRoundId++;
        RoundInfo storage round = rounds[currentRoundId];
        
        round.state = GameState.Joining;
        round.startTime = block.timestamp;
        round.joinDeadline = block.timestamp + JOIN_DURATION;
        round.currentRadius = INITIAL_RADIUS;
        // 初始圓心暫定 500 (中間)，直到正式開始才會隨機刷新
        round.currentCenterX = 500;
        round.currentCenterY = 500;
        
        emit GameRoundOpened(currentRoundId, round.joinDeadline);
    }

    /**
     * @notice 觸發遊戲進程 (開始遊戲 或 縮圈)
     * - 如果是 Joining -> 轉為 Battling (刷新圓心)
     * - 如果是 Battling -> 縮圈
     */
    function performShrink() external onlyOwner {
        RoundInfo storage round = rounds[currentRoundId];
        require(round.state != GameState.Inactive, "No active round");
        require(pendingAction == 0, "VRF Action pending");

        if (round.state == GameState.Joining) {
            // (3) 正式開始遊戲
            // 在開發測試時可以註解掉時間檢查，以便隨時開始
            // require(block.timestamp >= round.joinDeadline, "Join period not over");
            
            pendingAction = 1; // 1 = Start Game (Init Center)
            _requestRandomness();
            
        } else if (round.state == GameState.Battling) {
            // (4) 縮圈
            // require(block.timestamp >= round.lastActionTime + SHRINK_INTERVAL, "Too early to shrink");
            require(round.currentRadius > 0, "Already min radius");

            pendingAction = 2; // 2 = Shrink
            _requestRandomness();
        }
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
        
        RoundInfo storage round = rounds[currentRoundId];
        round.lastActionTime = block.timestamp;
        
        if (pendingAction == 1) {
            // (3) 遊戲正式開始：設定初始隨機圓心
            round.state = GameState.Battling;
            round.currentCenterX = newX;
            round.currentCenterY = newY;
            // 半徑保持初始值，或者你想要一開始就縮小也可以在這裡改
            round.currentRadius = INITIAL_RADIUS;
            
            emit GameBattlingStarted(currentRoundId, newX, newY);
            
            // 檢查是否有人運氣不好，一開始選的點就直接在圈外 (天譴?)
            _checkForElimination(currentRoundId);

        } else if (pendingAction == 2) {
            // (4) 縮圈
            round.currentCenterX = newX;
            round.currentCenterY = newY;
            round.currentRadius = round.currentRadius / 2; // 半徑減半

            emit ZoneShrunk(currentRoundId, newX, newY, round.currentRadius);
            
            // 執行淘汰檢查
            _checkForElimination(currentRoundId);
        }
        
        pendingAction = 0;
        
        // 檢查是否有贏家
        _checkForWinner(currentRoundId);
    }

    // --- Game Logic ---

    function getRoundState(uint256 roundId) external view returns (uint8) {
        return uint8(rounds[roundId].state);
    }

    function getCurrentRadius() public view returns (uint256) {
        return rounds[currentRoundId].currentRadius;
    }
    
    function currentCenterX() public view returns (uint256) {
        return rounds[currentRoundId].currentCenterX;
    }

    function currentCenterY() public view returns (uint256) {
        return rounds[currentRoundId].currentCenterY;
    }
    
    function isGameActive() public view returns (bool) {
        return rounds[currentRoundId].state != GameState.Inactive;
    }

    function getDistanceSq(uint256 x1, uint256 y1, uint256 x2, uint256 y2) public pure returns (uint256) {
        uint256 dx = x1 > x2 ? x1 - x2 : x2 - x1;
        uint256 dy = y1 > y2 ? y1 - y2 : y2 - y1;

        if (dx > MAP_SIZE / 2) dx = MAP_SIZE - dx;
        if (dy > MAP_SIZE / 2) dy = MAP_SIZE - dy;

        return dx * dx + dy * dy;
    }

    function checkElimination(uint256 tokenId) public view returns (bool) {
        if (!ticketInfo[tokenId].exists) return false;
        if (ticketInfo[tokenId].isEliminated) return true;
        
        uint256 roundId = ticketInfo[tokenId].roundId;
        RoundInfo storage round = rounds[roundId];
        
        if (round.state == GameState.Inactive && round.winnerId != 0 && round.winnerId != tokenId) {
            return true; // Round ended and you are not the winner
        }

        uint256 radius = round.currentRadius;
        uint256 distSq = getDistanceSq(ticketInfo[tokenId].x, ticketInfo[tokenId].y, round.currentCenterX, round.currentCenterY);
        
        return distSq > radius * radius;
    }

    // Chainlink Automation Interface
    function checkUpkeep(bytes calldata /* checkData */) external view returns (bool upkeepNeeded, bytes memory /* performData */) {
        RoundInfo storage round = rounds[currentRoundId];
        
        if (pendingAction != 0) return (false, "");
        if (round.state == GameState.Inactive) return (false, "");
        
        // 如果是 Joining 且時間到了 -> 需要切換到 Battling
        if (round.state == GameState.Joining) {
            upkeepNeeded = block.timestamp >= round.joinDeadline;
        } 
        // 如果是 Battling 且時間到了 -> 需要縮圈
        else if (round.state == GameState.Battling) {
            if (round.currentRadius == 0) return (false, "");
            upkeepNeeded = block.timestamp >= round.lastActionTime + SHRINK_INTERVAL;
        }
    }

    function performUpkeep(bytes calldata /* performData */) external {
        // 重用 performShrink 邏輯，但這裡可以加上更嚴格的時間檢查
        // 為了簡單起見，直接呼叫 performShrink (它會再次檢查狀態)
        this.performShrink(); 
    }

    function _checkForElimination(uint256 roundId) internal {
        RoundInfo storage round = rounds[roundId];
        uint256 radiusSq = round.currentRadius * round.currentRadius;
        
        uint256[] memory tickets = roundTickets[roundId];
        for (uint256 i = 0; i < tickets.length; i++) {
            uint256 tid = tickets[i];
            // 只檢查尚未淘汰的
            if (!ticketInfo[tid].isEliminated) {
                uint256 distSq = getDistanceSq(ticketInfo[tid].x, ticketInfo[tid].y, round.currentCenterX, round.currentCenterY);
                if (distSq > radiusSq) {
                    ticketInfo[tid].isEliminated = true;
                    emit PlayerEliminated(roundId, tid);
                }
            }
        }
    }

    function _checkForWinner(uint256 roundId) internal {
        RoundInfo storage round = rounds[roundId];
        // 如果還在 Joining 階段，不需要檢查贏家
        if (round.state != GameState.Battling) return;

        uint256[] memory tickets = roundTickets[roundId];
        if (tickets.length == 0) return;

        uint256 survivorCount = 0;
        uint256 lastSurvivor = 0;
        
        for (uint256 i = 0; i < tickets.length; i++) {
            uint256 tid = tickets[i];
            if (!ticketInfo[tid].isEliminated) {
                survivorCount++;
                lastSurvivor = tid;
            }
        }

        if (survivorCount == 1) {
            _declareWinner(roundId, lastSurvivor);
        } else if (round.currentRadius == 0 && survivorCount > 1) {
            // Sudden Death
            uint256 bestCandidate = 0;
            uint256 minDistSq = type(uint256).max;
            
            for (uint256 i = 0; i < tickets.length; i++) {
                uint256 tid = tickets[i];
                if (!ticketInfo[tid].isEliminated) {
                    uint256 distSq = getDistanceSq(ticketInfo[tid].x, ticketInfo[tid].y, round.currentCenterX, round.currentCenterY);
                    if (distSq < minDistSq) {
                        minDistSq = distSq;
                        bestCandidate = tid;
                    }
                }
            }
            _declareWinner(roundId, bestCandidate);
        } else if (survivorCount == 0 && tickets.length > 0) {
             // 所有人同時死光？
             round.state = GameState.Inactive;
             round.startTime = 0; // End marker
        }
    }

    function _declareWinner(uint256 roundId, uint256 winnerId) internal {
        RoundInfo storage round = rounds[roundId];
        round.winnerId = winnerId;
        round.state = GameState.Inactive;
        round.startTime = 0; // End marker if needed
        
        // 標記其他所有人為淘汰
        uint256[] memory tickets = roundTickets[roundId];
        for (uint256 i = 0; i < tickets.length; i++) {
            if (tickets[i] != winnerId) {
                ticketInfo[tickets[i]].isEliminated = true;
            }
        }
        
        emit WinnerDeclared(roundId, winnerId, 0);
    }

    // --- IPOLHook Implementation ---

    function beforeDeposit(
        address /* caller */,
        uint256 assets,
        uint256 /* shares */,
        bytes calldata data
    ) external view override onlyVault {
        require(assets == TICKET_PRICE, "Invalid ticket price");
        // 只要不是 Inactive，都可以存款 (Joining 存入本局, Battling 存入下局)
        require(rounds[currentRoundId].state != GameState.Inactive, "No active game");
        
        require(data.length == 64, "Invalid data length"); 
        (uint256 x, uint256 y) = abi.decode(data, (uint256, uint256));
        require(x < MAP_SIZE && y < MAP_SIZE, "Coordinates out of bounds");
    }

    function afterDeposit(
        address /* caller */,
        uint256 /* assets */,
        uint256 shares, // This is tokenId
        bytes calldata data
    ) external override onlyVault {
        (uint256 x, uint256 y) = abi.decode(data, (uint256, uint256));
        
        // (3) 決定這張票去哪裡
        // 如果現在是 Joining，加入 currentRoundId
        // 如果現在是 Battling，加入 currentRoundId + 1 (排隊下一局)
        uint256 targetRoundId = currentRoundId;
        if (rounds[currentRoundId].state == GameState.Battling) {
            targetRoundId = currentRoundId + 1;
        }
        
        ticketInfo[shares] = TicketData({
            x: x,
            y: y,
            isEliminated: false,
            exists: true,
            roundId: targetRoundId
        });
        
        roundTickets[targetRoundId].push(shares);
    }

    function onRedeemRequest(
        address /* caller */,
        uint256 shares,
        bytes calldata /* data */
    ) external override onlyVault {
        ticketInfo[shares].exists = false;
    }

    function getRedeemableAmount(
        uint256 tokenId,
        uint256 principal
    ) external view override returns (uint256) {
        uint256 roundId = ticketInfo[tokenId].roundId;
        RoundInfo storage round = rounds[roundId];
        
        // 如果回合還在進行中 (Joining 或 Battling)
        if (round.state != GameState.Inactive) {
             if (checkElimination(tokenId)) {
                 return principal; 
             } else {
                 // Early exit penalty
                 uint256 penalty = (principal * PENALTY_BASIS_POINTS) / 10000;
                 return principal - penalty;
             }
        } else {
            // 回合結束
            if (round.winnerId == tokenId) {
                return principal;
            } else {
                return principal;
            }
        }
    }

    function isWinner(uint256 tokenId) external view returns (bool) {
        if (!ticketInfo[tokenId].exists) return false;
        uint256 roundId = ticketInfo[tokenId].roundId;
        return rounds[roundId].winnerId == tokenId;
    }
}