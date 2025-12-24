// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAdapter} from "../interfaces/IAdapter.sol";
import {MasterVault} from "../MasterVault.sol";

/**
 * @dev Aerodrome 路由路徑結構
 */
struct Route {
    address from;
    address to;
    bool stable;
    address factory;
}

interface IAerodromeRouter {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Route[] calldata routes,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function addLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        bool stable,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);
}

interface IAerodromeGauge {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function getReward(address account) external;
    function balanceOf(address account) external view returns (uint256);
    function earned(address account, address token) external view returns (uint256);
}

interface IAerodromePair {
    function metadata() external view returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool st, address t0, address t1);
}

/**
 * @title AeroAdapter
 * @notice Proof of Luck 協議的 Aerodrome (Base) 適配器。
 * @dev 該策略使用穩定池（如 USDC-USDbC）來最小化無常損失：
 *      - 存款 (Deposit): 將 50% USDC 兌換為另一種代幣（如 USDbC），添加流動性，並在 Gauge 中質押 LP。
 *      - 贖回 (Redeem): 解除質押，移除流動性，將另一種代幣換回 USDC。
 *      - 收益 (Yield): 領取 AERO 獎勵，並將 AERO 換成 USDC。
 */
contract AeroAdapter is IAdapter, Ownable {
    IERC20 public immutable asset;       // 基礎資產 (USDC)
    IERC20 public immutable otherToken;  // 配對代幣 (如 USDbC)
    IERC20 public immutable rewardToken; // 獎勵代幣 (AERO)

    address public immutable router;     // Aerodrome Router
    address public immutable gauge;      // 質押激勵合約
    address public immutable lpToken;    // 流動性池代幣
    address public immutable factory;    // Aerodrome Factory
    address public immutable vault;      // 主金庫 (MasterVault) 地址

    bool public immutable stable;        // 是否使用穩定池 (Stable Pool) 路徑

    uint256 public totalPrincipal;       // 總本金
    uint256 public accumulatedPenalties; // 累計罰金（國庫收入）

    constructor(
        address _asset,
        address _otherToken,
        address _rewardToken,
        address _router,
        address _gauge,
        address _lpToken,
        address _factory,
        bool _stable,
        address _vault
    ) Ownable(msg.sender) {
        asset = IERC20(_asset);
        otherToken = IERC20(_otherToken);
        rewardToken = IERC20(_rewardToken);
        router = _router;
        gauge = _gauge;
        lpToken = _lpToken;
        factory = _factory;
        stable = _stable;
        vault = _vault;

        // 預先授權 Router 進行代幣交換與添加流動性
        asset.approve(router, type(uint256).max);
        otherToken.approve(router, type(uint256).max);
        IERC20(lpToken).approve(gauge, type(uint256).max);
        rewardToken.approve(router, type(uint256).max);
    }

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    /**
     * @dev 權限檢查：僅限金庫或已授權的 Hook 合約調用
     */
    modifier onlyVaultOrHook() {
        bool isHook = false;
        if (msg.sender != vault) {
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
     * @notice 執行存款策略：USDC -> LP -> Stake
     */
    function deposit(uint256 assets, bytes calldata /* data */) external override onlyVault returns (uint256 shares) {
        // 1. 從金庫轉入 USDC
        asset.transferFrom(msg.sender, address(this), assets);
        totalPrincipal += assets;

        // 2. 將約 50% USDC 兌換為配對代幣 (例如 USDbC)
        uint256 amountToSwap = assets / 2;
        
        Route[] memory routes = new Route[](1);
        routes[0] = Route({
            from: address(asset),
            to: address(otherToken),
            stable: stable,
            factory: factory
        });

        IAerodromeRouter(router).swapExactTokensForTokens(
            amountToSwap,
            0, // 此處為了演示簡化了滑點檢查，生產環境應計算 minAmountOut
            routes,
            address(this),
            block.timestamp
        );

        // 3. 添加流動性 (Add Liquidity)
        uint256 assetBalance = asset.balanceOf(address(this));
        uint256 otherBalance = otherToken.balanceOf(address(this));

        (,, uint256 liquidity) = IAerodromeRouter(router).addLiquidity(
            address(asset),
            address(otherToken),
            stable,
            assetBalance,
            otherBalance,
            0, // Min amount A
            0, // Min amount B
            address(this),
            block.timestamp
        );

        // 4. 將 LP 代幣質押到 Gauge 中賺取 AERO
        IAerodromeGauge(gauge).deposit(liquidity);

        // 回傳產生的 LP 數量作為份額 (shares)
        return liquidity;
    }

    /**
     * @notice 執行贖回策略：Unstake -> Remove Liquidity -> Swap back to USDC
     */
    function redeem(uint256 shares, uint256 principalToBurn, address receiver, address /* owner */) external override onlyVault returns (uint256 assets) {
        // 1. 從 Gauge 中提取 LP 代幣
        IAerodromeGauge(gauge).withdraw(shares);

        // 2. 移除流動性，換回兩種代幣 (USDC & USDbC)
        (uint256 amountA, uint256 amountB) = IAerodromeRouter(router).removeLiquidity(
            address(asset),
            address(otherToken),
            stable,
            shares,
            0,
            0,
            address(this),
            block.timestamp
        );

        // 3. 將配對代幣 (USDbC) 換回 USDC
        if (amountB > 0) {
            Route[] memory routes = new Route[](1);
            routes[0] = Route({
                from: address(otherToken),
                to: address(asset),
                stable: stable,
                factory: factory
            });

            uint256[] memory amounts = IAerodromeRouter(router).swapExactTokensForTokens(
                amountB,
                0,
                routes,
                address(this),
                block.timestamp
            );
            amountA += amounts[amounts.length - 1];
        }

        assets = amountA;

        // 4. 更新本金記錄
        if (principalToBurn > totalPrincipal) {
            totalPrincipal = 0;
        } else {
            totalPrincipal -= principalToBurn;
        }

        // 5. 處理結果：將贖回的 USDC 轉發給接收者
        asset.transfer(receiver, assets);
    }

    /**
     * @notice 獲取當前未實現收益（以獎勵代幣數量表示）
     */
    function getTotalYield() external view override returns (uint256) {
        // 返回目前已累積且可領取的 AERO 數量
        return IAerodromeGauge(gauge).earned(address(this), address(rewardToken));
    }

    /**
     * @notice 複利策略（目前 Aerodrome 適配器暫未實現自動複利）
     */
    function reinvestYield(uint256 amount) external override onlyVault {
        totalPrincipal += amount;
    }

    /**
     * @notice 提取金庫罰金（國庫收入）
     */
    function collectRevenue(uint256 amount, address receiver) external override onlyVault {
        uint256 toCollect = amount;
        if (amount == type(uint256).max) {
            toCollect = accumulatedPenalties;
        }
        
        if (toCollect > 0 && toCollect <= accumulatedPenalties) {
            accumulatedPenalties -= toCollect;
            asset.transfer(receiver, toCollect);
        }
    }

    /**
     * @notice 領取並實現收益：Claim AERO -> Swap to USDC -> Transfer
     */
    function collectYield(uint256 amount, address receiver) external override onlyVaultOrHook {
        // 1. 從 Gauge 領取 AERO 獎勵
        IAerodromeGauge(gauge).getReward(address(this));

        // 2. 將 AERO 換成 USDC
        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (rewardBalance > 0) {
            Route[] memory routes = new Route[](1);
            routes[0] = Route({
                from: address(rewardToken),
                to: address(asset),
                stable: false, // AERO-USDC 通常是波動池 (Volatile Pool)
                factory: factory
            });

            IAerodromeRouter(router).swapExactTokensForTokens(
                rewardBalance,
                0,
                routes,
                address(this),
                block.timestamp
            );
        }

        // 3. 結算並轉移 USDC 收益
        uint256 yieldInAsset = asset.balanceOf(address(this));
        
        // 確保轉移數量不超過合約持有的資產餘額
        if (amount > yieldInAsset) {
            amount = yieldInAsset;
        }
        
        if (amount > 0) {
            asset.transfer(receiver, amount);
        }
    }
}