// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {POLToken} from "./POLToken.sol";

contract POLStaking is ERC4626, ERC20Permit, ERC20Votes, Ownable {
    using SafeERC20 for IERC20;

    struct StakeInfo {
        uint256 amount;
        uint256 unlockTime;
    }

    mapping(address => StakeInfo) public stakes;
    uint256 public constant UNBONDING_PERIOD = 7 days;

    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event Slashed(address indexed user, uint256 amount);

    constructor(address _polToken) 
        ERC4626(IERC20(_polToken))
        ERC20("Staked POL", "sPOL") 
        ERC20Permit("Staked POL") 
        Ownable(msg.sender) 
    {}

    /**
     * @notice 質押 POL 代幣以接收 sPOL。
     * @dev 覆蓋 ERC4626 deposit 以添加鎖定邏輯。
     */
    function stake(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = deposit(assets, receiver);
        
        stakes[receiver].amount += shares; // 追蹤份額而非資產，用於鎖定
        stakes[receiver].unlockTime = block.timestamp + UNBONDING_PERIOD;

        // 如果尚未委託，則自動委託給自己
        if (delegates(receiver) == address(0)) {
            _delegate(receiver, receiver);
        }

        emit Staked(receiver, assets);
    }
    
    /**
     * @notice 解質押 sPOL 以接收 POL。
     * @dev 覆蓋 ERC4626 redeem 以檢查鎖定邏輯。
     */
    function unstake(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(stakes[owner].amount >= shares, "Insufficient stake");
        require(block.timestamp >= stakes[owner].unlockTime, "Stake is locked");

        stakes[owner].amount -= shares;
        assets = redeem(shares, receiver, owner);
        
        emit Unstaked(owner, assets);
    }

    function slash(address user, uint256 shares) external onlyOwner {
        require(stakes[user].amount >= shares, "Insufficient stake to slash");
        stakes[user].amount -= shares;
        
        // 銷毀 sPOL 份額，但不返還資產。
        // 資產保留在金庫中，增加其他所有人的股價。
        _burn(user, shares);
        
        emit Slashed(user, shares);
    }

    // ERC4626/ERC20/ERC20Votes 兼容性的覆蓋

    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
