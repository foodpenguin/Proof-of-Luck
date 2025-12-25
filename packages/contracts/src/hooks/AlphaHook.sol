// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPOLHook} from "../interfaces/IPOLHook.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {VRFConsumerBaseV2} from "../interfaces/VRFConsumerBaseV2.sol";
import {MasterVault} from "../MasterVault.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IVRFCoordinator} from "../interfaces/IVRFCoordinator.sol";

interface IPOLStaking {
    function totalSupply() external view returns (uint256);
}

/**
 * @title AlphaHook
 * @notice Proof of Luck Alpha 池（每週抽獎）。
 * @dev 治理控制的每週彩票，具有槓桿上限和費用。
 */
contract AlphaHook is IPOLHook, Ownable, VRFConsumerBaseV2 {
    address public vault;
    address public governance;
    IPOLStaking public staking;

    // VRF 配置
    IVRFCoordinator public vrfCoordinator;
    bytes32 public keyHash;
    uint64 public subscriptionId;
    uint32 public callbackGasLimit = 100000;
    uint16 public requestConfirmations = 3;

    // 彩票狀態
    uint256 public lastDrawTimestamp;
    uint256 public drawInterval = 7 days;
    uint256 public currentDrawId;
    bool public isDrawPending;

    // 參與者
    uint256[] public activeTickets;
    mapping(uint256 => uint256) public ticketIndex;
    mapping(uint256 => bool) public isTicketActive;

    // NFT Evolution (Weight)
    mapping(uint256 => uint256) public nftWeight;

    // TVL Tracking for Leverage Check
    uint256 public totalValueLocked;

    event DrawRequested(uint256 indexed drawId, uint256 requestId);
    event DrawCompleted(uint256 indexed drawId, uint256 winnerTokenId, uint256 randomWord);
    event TicketEvolved(uint256 indexed tokenId, uint256 newWeight);
    event GovernanceUpdated(address indexed newGovernance);
    event DrawIntervalUpdated(uint256 newInterval);
    event StakingUpdated(address indexed newStaking);

    constructor(
        address _vault,
        address _vrfCoordinator,
        bytes32 _keyHash,
        uint64 _subId,
        address _staking
    ) Ownable(msg.sender) VRFConsumerBaseV2(_vrfCoordinator) {
        vault = _vault;
        vrfCoordinator = IVRFCoordinator(_vrfCoordinator);
        keyHash = _keyHash;
        subscriptionId = _subId;
        staking = IPOLStaking(_staking);
        lastDrawTimestamp = block.timestamp;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == governance || msg.sender == owner(), "Only governance");
        _;
    }

    function setGovernance(address _governance) external onlyOwner {
        governance = _governance;
        emit GovernanceUpdated(_governance);
    }

    function setStaking(address _staking) external onlyOwner {
        staking = IPOLStaking(_staking);
        emit StakingUpdated(_staking);
    }

    function setDrawInterval(uint256 _interval) external onlyGovernance {
        drawInterval = _interval;
        emit DrawIntervalUpdated(_interval);
    }

    function beforeDeposit(
        address, uint256 assets, uint256, bytes calldata
    ) external view override onlyVault {
        require(!isDrawPending, "Draw in progress");
        
        // Leverage Check: Staked Value >= 25% of (TVL + Deposit)
        if (address(staking) != address(0)) {
            uint256 stakedValue = staking.totalSupply();
            
            // Normalize decimals
            address asset = address(MasterVault(vault).ASSET());
            uint8 assetDecimals = IERC20Metadata(asset).decimals();
            
            uint256 tvl18 = totalValueLocked + assets;
            if (assetDecimals < 18) {
                tvl18 = tvl18 * (10 ** (18 - assetDecimals));
            }
            
            require(tvl18 <= stakedValue * 4, "Leverage cap exceeded");
        }
    }

    function afterDeposit(
        address, uint256 assets, uint256 shares, bytes calldata
    ) external override onlyVault {
        uint256 tokenId = shares;
        activeTickets.push(tokenId);
        ticketIndex[tokenId] = activeTickets.length - 1;
        isTicketActive[tokenId] = true;
        nftWeight[tokenId] = 100;
        totalValueLocked += assets;
    }

    function onRedeemRequest(
        address, uint256 shares, bytes calldata
    ) external override onlyVault {
        require(!isDrawPending, "Draw in progress");
        
        uint256 tokenId = shares;
        require(isTicketActive[tokenId], "Ticket not active");

        // Update TVL
        (uint128 assets, , , , , , , ) = MasterVault(vault).tickets(tokenId);
        if (totalValueLocked >= assets) {
            totalValueLocked -= assets;
        } else {
            totalValueLocked = 0;
        }

        uint256 index = ticketIndex[tokenId];
        uint256 lastTokenId = activeTickets[activeTickets.length - 1];

        activeTickets[index] = lastTokenId;
        ticketIndex[lastTokenId] = index;
        activeTickets.pop();

        delete ticketIndex[tokenId];
        delete isTicketActive[tokenId];
        delete nftWeight[tokenId];
    }

    function getRedeemableAmount(
        uint256, uint256 principal
    ) external pure override returns (uint256) {
        return principal;
    }

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
            1
        );

        emit DrawRequested(currentDrawId, requestId);
    }

    function fulfillRandomWords(uint256, uint256[] memory randomWords) internal override {
        require(isDrawPending, "No pending draw");
        isDrawPending = false;
        
        uint256 randomWord = randomWords[0];
        
        uint256 totalWeighted = 0;
        uint256[] memory weights = new uint256[](activeTickets.length);
        
        for (uint256 i = 0; i < activeTickets.length; i++) {
            uint256 tid = activeTickets[i];
            (uint128 assets, , , , , , , ) = MasterVault(vault).tickets(tid);
            uint256 principal = uint256(assets);
            uint256 w = nftWeight[tid];
            if (w == 0) w = 100;
            
            uint256 effective = principal * w;
            weights[i] = effective;
            totalWeighted += effective;
        }
        
        if (totalWeighted == 0) {
            lastDrawTimestamp = block.timestamp;
            return;
        }
        
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
        
        if (winnerId != 0) {
            // Fee Logic: 20% to Governance
            address adapter = MasterVault(vault).hookAdapters(address(this));
            if (adapter != address(0) && governance != address(0)) {
                uint256 totalYield = IAdapter(adapter).getTotalYield();
                uint256 fee = totalYield * 20 / 100;
                if (fee > 0) {
                    IAdapter(adapter).collectYield(fee, governance);
                }
            }

            MasterVault(vault).distributeYieldToTicket(winnerId);
            
            // Update TVL with the reinvested yield
            if (adapter != address(0)) {
                 uint256 remainingYield = IAdapter(adapter).getTotalYield();
                 totalValueLocked += remainingYield;
            }

            nftWeight[winnerId] = 100;
            MasterVault(vault).updateTicketMultiplier(winnerId, 100); // Sync
            emit DrawCompleted(currentDrawId, winnerId, randomWord);
        }
        
        uint256 count = activeTickets.length / 100;
        if (count == 0 && activeTickets.length > 0) count = 1;
        
        for (uint256 i = 0; i < count; i++) {
            uint256 idx = uint256(keccak256(abi.encode(randomWord, i))) % activeTickets.length;
            uint256 tid = activeTickets[idx];
            if (tid != winnerId) {
                nftWeight[tid] += 5;
                MasterVault(vault).updateTicketMultiplier(tid, uint16(nftWeight[tid])); // Sync
                emit TicketEvolved(tid, nftWeight[tid]);
            }
        }
        
        lastDrawTimestamp = block.timestamp;
    }
}
