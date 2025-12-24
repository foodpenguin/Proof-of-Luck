// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {IAavePool} from "../interfaces/IAavePool.sol";
import {MasterVault} from "../MasterVault.sol";

/**
 * @title AaveAdapter
 * @notice 對接 Aave V3 的策略適配器。
 * @dev 負責將 USDC 存入 Aave V3 Pool 並管理 aToken。
 */
contract AaveAdapter is IAdapter, Ownable {
    /// @notice 底層資產 (USDC)。
    IERC20 public immutable asset;

    /// @notice Aave V3 Pool 合約。
    IAavePool public immutable aavePool;
    
    /// @notice 對應的 aToken (例如 aUSDC)。
    address public immutable aToken;

    /// @notice MasterVault 地址 (唯一有權呼叫者)。
    address public vault;

    /// @notice 總存入本金 (用於計算 Yield)。
    uint256 public totalPrincipal;

    /// @notice 累積的罰金 (Protocol Revenue)。
    uint256 public accumulatedPenalties;

    constructor(address _asset, address _aavePool, address _aToken, address _vault) Ownable(msg.sender) {
        require(_asset != address(0), "Invalid asset");
        require(_aavePool != address(0), "Invalid pool");
        require(_aToken != address(0), "Invalid aToken");
        require(_vault != address(0), "Invalid vault");
        
        asset = IERC20(_asset);
        aavePool = IAavePool(_aavePool);
        aToken = _aToken;
        vault = _vault;
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    modifier onlyVaultOrHook() {
        bool isHook = false;
        if (msg.sender != vault) {
            // Check if msg.sender is a registered hook for this adapter
            try MasterVault(vault).hookAdapters(msg.sender) returns (address adapter) {
                if (adapter == address(this)) {
                    isHook = true;
                }
            } catch {}
        }
        require(msg.sender == vault || isHook, "Only vault or hook");
        _;
    }

    /**
     * @notice 獲取當前累積的總收益 (Yield)。
     * @dev Yield = Balance - Principal - Penalties
     */
    function getTotalYield() external view returns (uint256) {
        uint256 balance = IERC20(aToken).balanceOf(address(this));
        uint256 liabilities = totalPrincipal + accumulatedPenalties;
        return balance > liabilities 
            ? balance - liabilities 
            : 0;
    }

    /**
     * @notice 將收益再投資 (增加本金負債)。
     */
    function reinvestYield(uint256 amount) external override onlyVault {
        totalPrincipal += amount;
    }

    /**
     * @notice 收集協議收入 (如罰金)。
     */
    function collectRevenue(uint256 amount, address receiver) external override onlyVault {
        uint256 toCollect = amount;
        if (amount == type(uint256).max) {
            toCollect = accumulatedPenalties;
        }
        
        require(toCollect <= accumulatedPenalties, "Insufficient penalties");
        if (toCollect > 0) {
            accumulatedPenalties -= toCollect;
            // Withdraw from Aave and send to receiver
            aavePool.withdraw(address(asset), toCollect, receiver);
        }
    }

    /**
     * @notice 收集收益作為費用 (Collect Yield as Fee)。
     */
    function collectYield(uint256 amount, address receiver) external override onlyVaultOrHook {
        uint256 currentYield = this.getTotalYield();
        require(amount <= currentYield, "Insufficient yield");
        
        if (amount > 0) {
            // Withdraw from Aave and send to receiver
            aavePool.withdraw(address(asset), amount, receiver);
        }
    }

    /**
     * @notice 將資產存入 Aave。
     * @dev 遵循 Checks-Effects-Interactions。
     */
    function deposit(uint256 assets, bytes calldata /* data */) external override onlyVault returns (uint256 shares) {
        require(assets > 0, "Zero assets");

        // 0. Effects: Update principal
        totalPrincipal += assets;

        // 1. Interactions: Pull funds from Vault
        // Vault has already approved this adapter
        bool success = asset.transferFrom(msg.sender, address(this), assets);
        require(success, "Transfer from Vault failed");

        // 2. Interactions: Approve Aave Pool
        // 為了節省 Gas，可以考慮在建構時無限授權，但為了安全這裡每次檢查或授權
        // 這裡簡化為每次授權 (生產環境可優化)
        asset.approve(address(aavePool), assets);

        // 3. Interactions: Supply to Aave
        // onBehalfOf = address(this) -> Adapter 持有 aToken
        // referralCode = 0
        aavePool.supply(address(asset), assets, address(this), 0);

        // 4. Return shares (1:1 for simplicity in this version, or aToken balance)
        // Aave aToken is 1:1 pegged to underlying usually, but rebasing.
        // 這裡簡單返回存入的數量作為份額
        return assets;
    }

    /**
     * @notice 從 Aave 贖回資產。
     */
    function redeem(uint256 shares, uint256 principalToBurn, address receiver, address /* owner */) external override onlyVault returns (uint256 assets) {
        require(shares > 0, "Zero shares");

        // 0. Effects: Update principal
        // 使用傳入的 principalToBurn 來更新負債
        if (principalToBurn > totalPrincipal) {
            totalPrincipal = 0;
        } else {
            totalPrincipal -= principalToBurn;
        }

        // 如果贖回金額小於本金銷毀量 (即有罰金)，記錄罰金
        // 例如: 贖回 90，銷毀本金 100 -> 罰金 10
        if (shares < principalToBurn) {
            accumulatedPenalties += (principalToBurn - shares);
        }

        // 1. Interactions: Withdraw from Aave
        // withdraw(asset, amount, to)
        // 這裡假設 shares = amount (1:1)
        assets = aavePool.withdraw(address(asset), shares, receiver);
        
        return assets;
    }

    /**
     * @notice 緊急提款 (僅限 Owner)。
     * @dev 防止資金卡死。
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyOwner {
        IERC20(token).transfer(to, amount);
    }
}
