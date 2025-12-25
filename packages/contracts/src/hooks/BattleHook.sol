// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPOLHook} from "../interfaces/IPOLHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "../interfaces/VRFConsumerBaseV2.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";

/**
 * @title BattleHook
 * @notice Battle Royale Logic Hook (Round-Based).
 * @dev Supports infinite replayability via Rounds (Epochs).
 */
contract BattleHook is IPOLHook, Ownable, VRFConsumerBaseV2 {
    address public immutable vault;
    
    // VRF Config
    IVRFCoordinator public vrfCoordinator;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 2500000;
    uint16 public requestConfirmations = 3;

    // Game Constants
    uint256 public constant MAP_SIZE = 1000;
    uint256 public constant INITIAL_RADIUS = 500;
    uint256 public constant TICKET_PRICE = 100 * 1e6; // 100 USDC
    uint256 public constant PENALTY_BASIS_POINTS = 1000; // 10% (1000/10000)
    uint256 public constant SHRINK_INTERVAL = 84 hours;

    struct TicketData {
        uint256 x;
        uint256 y;
        bool isEliminated;
        bool exists;
        uint256 roundId; // Track which round this ticket belongs to
    }

    struct RoundInfo {
        uint256 startTime;
        uint256 endTime;
        uint256 currentCenterX;
        uint256 currentCenterY;
        uint256 currentRadius;
        bool isActive;
        uint256 winnerId;
    }

    // State
    uint256 public currentRoundId;
    uint256 public lastShrinkTimestamp;
    mapping(uint256 => RoundInfo) public rounds;
    mapping(uint256 => TicketData) public ticketInfo;
    mapping(uint256 => uint256[]) public roundTickets; // roundId => ticketIds

    // VRF State
    uint8 public pendingAction; // 0=None, 1=Start, 2=Shrink
    
    // Events
    event GameStarted(uint256 indexed roundId, uint256 startTime);
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
        
        // Initialize Round 0 (Dummy)
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
     * @notice Start a new round.
     * @dev Increments roundId, sets state to Active.
     */
    function startNewRound() external onlyOwner {
        require(!rounds[currentRoundId].isActive, "Current round still active");
        require(pendingAction == 0, "Action pending");
        
        currentRoundId++;
        
        rounds[currentRoundId].isActive = true;
        rounds[currentRoundId].startTime = block.timestamp;
        rounds[currentRoundId].currentRadius = INITIAL_RADIUS;
        rounds[currentRoundId].currentCenterX = 500; // Default, will be randomized
        rounds[currentRoundId].currentCenterY = 500; // Default, will be randomized
        
        lastShrinkTimestamp = block.timestamp;

        // Request initial random center
        pendingAction = 1; // Start
        _requestRandomness();
        
        emit GameStarted(currentRoundId, block.timestamp);
    }

    /**
     * @notice Trigger zone shrink for the CURRENT round.
     */
    function performShrink() external onlyOwner {
        require(rounds[currentRoundId].isActive, "Game not active");
        require(pendingAction == 0, "Action pending");
        require(rounds[currentRoundId].currentRadius > 0, "Already min radius");
        
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
        
        RoundInfo storage round = rounds[currentRoundId];
        
        round.currentCenterX = newX;
        round.currentCenterY = newY;
        
        if (pendingAction == 1) {
            // Start Game: Reset radius
            round.currentRadius = INITIAL_RADIUS;
        } else if (pendingAction == 2) {
            // Shrink: Halve radius
            round.currentRadius = round.currentRadius / 2;
        }
        
        pendingAction = 0;
        emit ZoneShrunk(currentRoundId, round.currentCenterX, round.currentCenterY, round.currentRadius);
        
        // Check for winner after shrink
        _checkForWinner(currentRoundId);
    }

    // --- Game Logic ---

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
        return rounds[currentRoundId].isActive;
    }

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

    function checkElimination(uint256 tokenId) public view returns (bool) {
        if (!ticketInfo[tokenId].exists) return false;
        if (ticketInfo[tokenId].isEliminated) return true;
        
        uint256 roundId = ticketInfo[tokenId].roundId;
        RoundInfo storage round = rounds[roundId];
        
        // If round is ended, use the final state (already captured in isEliminated or winner)
        // But for dynamic checking during the game:
        if (!round.isActive && round.endTime > 0) {
             // Round ended, if not marked eliminated, they survived? 
             // Actually, if round ended, winner is declared. Everyone else is eliminated.
             return ticketInfo[tokenId].isEliminated;
        }

        uint256 radius = round.currentRadius;
        uint256 distSq = getDistanceSq(ticketInfo[tokenId].x, ticketInfo[tokenId].y, round.currentCenterX, round.currentCenterY);
        
        return distSq > radius * radius;
    }

    function checkUpkeep(bytes calldata /* checkData */) external view returns (bool upkeepNeeded, bytes memory /* performData */) {
        if (!rounds[currentRoundId].isActive) return (false, "");
        if (pendingAction != 0) return (false, "");
        if (rounds[currentRoundId].currentRadius == 0) return (false, "");
        
        upkeepNeeded = (block.timestamp - lastShrinkTimestamp) > SHRINK_INTERVAL;
    }

    function performUpkeep(bytes calldata /* performData */) external {
        if (!rounds[currentRoundId].isActive) return;
        if (pendingAction != 0) return;
        if (rounds[currentRoundId].currentRadius == 0) return;
        if ((block.timestamp - lastShrinkTimestamp) <= SHRINK_INTERVAL) return;

        lastShrinkTimestamp = block.timestamp;
        pendingAction = 2; // Shrink
        _requestRandomness();
    }

    function _checkForWinner(uint256 roundId) internal {
        RoundInfo storage round = rounds[roundId];
        if (!round.isActive) return;

        uint256[] memory tickets = roundTickets[roundId];
        if (tickets.length == 0) return;

        uint256 survivorCount = 0;
        uint256 lastSurvivor = 0;
        
        // Check survivors
        for (uint256 i = 0; i < tickets.length; i++) {
            uint256 tid = tickets[i];
            if (!ticketInfo[tid].isEliminated) {
                // Re-check dynamic elimination
                uint256 distSq = getDistanceSq(ticketInfo[tid].x, ticketInfo[tid].y, round.currentCenterX, round.currentCenterY);
                if (distSq > round.currentRadius * round.currentRadius) {
                    ticketInfo[tid].isEliminated = true;
                    emit PlayerEliminated(roundId, tid);
                } else {
                    survivorCount++;
                    lastSurvivor = tid;
                }
            }
        }

        if (survivorCount == 1) {
            _declareWinner(roundId, lastSurvivor);
        } else if (round.currentRadius == 0 && survivorCount > 1) {
            // Sudden Death: Closest to center
            uint256 minDistSq = type(uint256).max;
            uint256 bestCandidate = 0;
            
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
             // Everyone died? Should not happen if logic is correct, but just in case end round
             round.isActive = false;
             round.endTime = block.timestamp;
        }
    }

    function _declareWinner(uint256 roundId, uint256 winnerId) internal {
        RoundInfo storage round = rounds[roundId];
        round.winnerId = winnerId;
        round.isActive = false;
        round.endTime = block.timestamp;
        
        // Mark all others as eliminated (if not already)
        uint256[] memory tickets = roundTickets[roundId];
        for (uint256 i = 0; i < tickets.length; i++) {
            if (tickets[i] != winnerId) {
                ticketInfo[tickets[i]].isEliminated = true;
            }
        }
        
        emit WinnerDeclared(roundId, winnerId, 0); // Prize calculated at redeem
    }

    // --- IPOLHook Implementation ---

    function beforeDeposit(
        address /* caller */,
        uint256 assets,
        uint256 /* shares */,
        bytes calldata data
    ) external view override onlyVault {
        require(assets == TICKET_PRICE, "Invalid ticket price");
        require(rounds[currentRoundId].isActive, "Round not active");
        
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
            exists: true,
            roundId: currentRoundId
        });
        
        roundTickets[currentRoundId].push(shares);
    }

    function onRedeemRequest(
        address /* caller */,
        uint256 shares,
        bytes calldata /* data */
    ) external override onlyVault {
        // Just cleanup if needed, but we keep history in roundTickets
        // We can mark as not exists to prevent double logic if needed, 
        // but ticket is burned by Vault anyway.
        ticketInfo[shares].exists = false;
    }

    function getRedeemableAmount(
        uint256 tokenId,
        uint256 principal
    ) external view override returns (uint256) {
        uint256 roundId = ticketInfo[tokenId].roundId;
        RoundInfo storage round = rounds[roundId];
        
        // If round is still active, and user is not eliminated, they are "Early Exiting"
        if (round.isActive) {
             if (checkElimination(tokenId)) {
                 return principal; // Eliminated, get principal
             } else {
                 // Early exit penalty
                 uint256 penalty = (principal * PENALTY_BASIS_POINTS) / 10000;
                 return principal - penalty;
             }
        } else {
            // Round Ended
            if (round.winnerId == tokenId) {
                // Winner gets Principal + Yield (Yield is handled by Vault, here we return Principal)
                return principal;
            } else {
                return principal;
            }
        }
    }

    /**
     * @notice Check if a ticket is the winner of its round.
     * @dev Used by MasterVault to determine if yield should be paid out.
     */
    function isWinner(uint256 tokenId) external view returns (bool) {
        if (!ticketInfo[tokenId].exists) return false;
        uint256 roundId = ticketInfo[tokenId].roundId;
        return rounds[roundId].winnerId == tokenId;
    }
}
