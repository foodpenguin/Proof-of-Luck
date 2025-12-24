// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/governance/POLToken.sol";
import "../src/governance/POLStaking.sol";
import "../src/governance/POLTimelock.sol";
import "../src/governance/POLGovernor.sol";
import "../src/MasterVault.sol";
import "../src/ZapRouter.sol";
import "../src/TicketMarketplace.sol";
import "../src/hooks/AlphaHook.sol";
import "../src/hooks/BattleHook.sol";
import "../src/hooks/GeneralHook.sol";
import "../src/mocks/VRFCoordinatorMock.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/adapters/AeroAdapter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/TicketDescriptor.sol";
import "./helpers/LiquidityHelper.sol";
import "forge-std/Test.sol"; 

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool);
}

/**
 * @title DeployFork
 * @dev 用於 Base 主網分叉環境的部署腳本
 * 涵蓋治理代幣、金庫、掛鉤器（Hooks）、適配器（Adapters）及流動性初始化
 */
contract DeployFork is Script {
    using stdStorage for StdStorage;

    // --- Base 主網合約地址清單 ---
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant A_USDC = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;
    address constant V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02 (Universal Router)
    address constant WHALE = 0xd0b53D9277642d899DF5C87A3966A349A798F224; // USDC/WETH 0.05% 池的大戶地址

    // --- Aerodrome (Base 生態 DEX) 相關地址 ---
    address constant AERO_ROUTER = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;
    address constant AERO_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address constant AERO_TOKEN = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
    address constant AERO_USDC_USDBC_POOL = 0x27a8Afa3Bd49406e48a074350fB7b2020c43B2bD;
    address constant AERO_USDC_USDBC_GAUGE = 0x1Cfc45C5221A07DA0DE958098A319a29FbBD66fE;

    function run() external {
        // 設定部署者私鑰，優先從環境變數讀取，否則使用 Anvil 預設私鑰
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Starting deployment from:", deployer);

        // 如果是本地開發環境 (Anvil)，進行初始資金注資
        if (block.chainid == 31337) {
            uint256 bal = IERC20(USDC).balanceOf(deployer);
            console.log("Deployer USDC Balance:", bal);
            
            if (bal < 5000000 * 1e6) {
                console.log("WARNING: Deployer USDC balance is low. Please run FundAccount.s.sol first.");
            }
        }

        vm.startBroadcast(deployerPrivateKey);

        // 1. 部署治理代幣 (POLToken)
        POLToken polToken = new POLToken();
        console.log("POLToken deployed at:", address(polToken));

        // 2. 部署治理架構 (Timelock & Governor)
        // 設定提案者與執行者
        address[] memory proposers = new address[](1);
        proposers[0] = deployer;
        address[] memory executors = new address[](1);
        executors[0] = address(0); // 允許任何人執行已通過公示期的提案
        
        POLTimelock timelock = new POLTimelock(
            1 days, // 公示期延遲
            proposers,
            executors,
            deployer
        );
        console.log("POLTimelock deployed at:", address(timelock));

        POLGovernor governor = new POLGovernor(polToken, timelock);
        console.log("POLGovernor deployed at:", address(governor));

        // 3. 部署質押合約 (POLStaking)
        POLStaking polStaking = new POLStaking(address(polToken));
        console.log("POLStaking deployed at:", address(polStaking));

        // 4. 部署核心主金庫 (MasterVault) - 以 USDC 為基礎資產
        MasterVault masterVault = new MasterVault(USDC);
        console.log("MasterVault deployed at:", address(masterVault));

        // 4.1 部署並設定 TicketDescriptor
        TicketDescriptor descriptor = new TicketDescriptor();
        console.log("TicketDescriptor deployed at:", address(descriptor));
        masterVault.setDescriptor(address(descriptor));

        // 5. 部署隨機數模擬合約 (VRFCoordinatorMock) - 用於測試環境的隨機需求
        VRFCoordinatorMock vrfCoordinator = new VRFCoordinatorMock();
        console.log("VRFCoordinatorMock deployed at:", address(vrfCoordinator));

        // 6. 部署金庫策略掛鉤器 (Hooks)
        AlphaHook alphaHook;
        BattleHook battleHook;
        GeneralHook generalHook;
        {
            bytes32 keyHash = bytes32(0);
            uint64 subId = 1;

            // AlphaHook: 模式 1 (結合質押回報)
            alphaHook = new AlphaHook(
                address(masterVault),
                address(vrfCoordinator),
                keyHash,
                subId,
                address(polStaking)
            );
            console.log("AlphaHook deployed at:", address(alphaHook));

            // BattleHook: 模式 2 (對戰邏輯)
            battleHook = new BattleHook(
                address(masterVault),
                address(vrfCoordinator),
                keyHash,
                subId
            );
            console.log("BattleHook deployed at:", address(battleHook));

            // GeneralHook: 模式 3 (通用收益策略)
            generalHook = new GeneralHook(
                address(masterVault),
                address(vrfCoordinator),
                keyHash,
                subId
            );
            console.log("GeneralHook deployed at:", address(generalHook));
        }

        // 7. 部署收益適配器 (Adapters)
        AaveAdapter aaveAdapter;
        AeroAdapter aeroAdapter;
        {
            // Aave 收益適配器
            aaveAdapter = new AaveAdapter(
                USDC,
                AAVE_POOL,
                A_USDC,
                address(masterVault)
            );
            console.log("AaveAdapter deployed at:", address(aaveAdapter));

            // Aerodrome 流動性挖礦適配器
            aeroAdapter = new AeroAdapter(
                USDC,
                USDbC,
                AERO_TOKEN,
                AERO_ROUTER,
                AERO_USDC_USDBC_GAUGE,
                AERO_USDC_USDBC_POOL,
                AERO_FACTORY,
                true, // 使用穩定池 (Stable Pool)
                address(masterVault)
            );
            console.log("AeroAdapter deployed at:", address(aeroAdapter));
        }

        // 8. 在主金庫中註冊模式與對應的掛鉤器/適配器
        masterVault.registerMode(1, address(alphaHook));
        masterVault.registerMode(2, address(battleHook));
        masterVault.registerMode(3, address(generalHook));
        
        // 為 GeneralHook 設定預設收益適配器 (例如 Aave)
        masterVault.setAdapter(address(generalHook), address(aaveAdapter));
        console.log("Hooks and Adapters registration complete");

        // 9. 部署兌換路由 (ZapRouter) - 支持資產快速轉換
        ZapRouter zapRouter = new ZapRouter(
            address(masterVault),
            USDC,
            SWAP_ROUTER,
            WETH
        );
        console.log("ZapRouter deployed at:", address(zapRouter));

        // 10. 部署門票市場 (TicketMarketplace)
        TicketMarketplace marketplace = new TicketMarketplace(
            address(masterVault),
            USDC,
            deployer // 暫時設定部署者為國庫受益人
        );
        console.log("TicketMarketplace deployed at:", address(marketplace));

        // 11. 初始化 Uniswap V3 流動性池 (POL/USDC)
        {
            LiquidityHelper liquidityHelper = new LiquidityHelper();
            console.log("LiquidityHelper deployed at:", address(liquidityHelper));

            // 決定 Token0 與 Token1 的順序
            address token0 = address(polToken) < USDC ? address(polToken) : USDC;
            address token1 = address(polToken) < USDC ? USDC : address(polToken);
            uint24 fee = 3000; // 手續費率 0.3%
            // 初始化價格設定為 1:1 (sqrtPriceX96)
            uint160 sqrtPriceX96 = 79228162514264337593543950336; 

            IUniswapV3Factory factory = IUniswapV3Factory(V3_FACTORY);
            address pool = factory.getPool(token0, token1, fee);
            
            // 如果池子不存在則創建
            if (pool == address(0)) {
                pool = factory.createPool(token0, token1, fee);
                IUniswapV3Pool(pool).initialize(sqrtPriceX96);
                console.log("Uniswap V3 Pool created at:", pool);
            } else {
                console.log("Uniswap V3 Pool already exists at:", pool);
            }

            // --- 添加初始流動性 ---
            uint256 amountPOL = 10000 * 1e18;
            uint256 amountUSDC = 10000 * 1e6;

            // 轉移代幣至輔助合約以執行添加流動性操作
            polToken.transfer(address(liquidityHelper), amountPOL);
            
            uint256 usdcBal = IERC20(USDC).balanceOf(deployer);
            if (usdcBal >= amountUSDC) {
                IERC20(USDC).transfer(address(liquidityHelper), amountUSDC);
                
                // 設定價格區間 (這裡設定為全範圍 Full Range 以確保簡易性)
                int24 tickSpacing = 60;
                int24 tickLower = -887220; 
                int24 tickUpper = 887220;
                
                // 根據 tickSpacing 對齊 Tick
                tickLower = (tickLower / tickSpacing) * tickSpacing;
                tickUpper = (tickUpper / tickSpacing) * tickSpacing;

                uint128 liquidity = 10000 * 1e6; // 初始流動性數量級

                try liquidityHelper.addLiquidity(
                    pool,
                    tickLower,
                    tickUpper,
                    liquidity,
                    token0,
                    token1
                ) {
                    console.log("Liquidity successfully added to the pool");
                } catch Error(string memory reason) {
                    console.log("Failed to add liquidity. Reason:", reason);
                } catch {
                    console.log("Failed to add liquidity due to an unknown error");
                }
            } else {
                console.log("Skipping liquidity addition: Insufficient USDC balance");
            }
        }

        // 12. 確保 WETH/USDC 0.05% 池有足夠流動性 (修復 Zap 問題)
        {
            LiquidityHelper liquidityHelper = new LiquidityHelper();
            address token0 = WETH < USDC ? WETH : USDC;
            address token1 = WETH < USDC ? USDC : WETH;
            uint24 fee = 500; // 0.05%
            
            IUniswapV3Factory factory = IUniswapV3Factory(V3_FACTORY);
            address pool = factory.getPool(token0, token1, fee);
            
            if (pool != address(0)) {
                console.log("Found WETH/USDC 0.05% pool at:", pool);
                
                // Wrap ETH to WETH
                uint256 amountWETH = 1000 ether; // Increase to 1000 ETH
                (bool success,) = WETH.call{value: amountWETH}(abi.encodeWithSignature("deposit()"));
                require(success, "WETH deposit failed");
                
                uint256 amountUSDC = 3000000 * 1e6; // Increase to 3M USDC
                
                // Transfer to LiquidityHelper
                IERC20(WETH).transfer(address(liquidityHelper), amountWETH);
                
                uint256 usdcBal = IERC20(USDC).balanceOf(deployer);
                if (usdcBal >= amountUSDC) {
                    IERC20(USDC).transfer(address(liquidityHelper), amountUSDC);
                    
                    // 0.05% fee has tickSpacing 10
                    int24 tickSpacing = 10;
                    int24 tickLower = -887200; 
                    int24 tickUpper = 887200;
                    
                    try liquidityHelper.addLiquidity(
                        pool,
                        tickLower,
                        tickUpper,
                        uint128(amountUSDC * 10000), // Boost liquidity amount (approx sqrt(x*y))
                        token0,
                        token1
                    ) {
                        console.log("Added liquidity to WETH/USDC pool");
                    } catch Error(string memory reason) {
                        console.log("Failed to add WETH/USDC liquidity:", reason);
                    } catch {
                        console.log("Failed to add WETH/USDC liquidity (unknown)");
                    }
                } else {
                    console.log("Skipping WETH/USDC liquidity: Insufficient USDC");
                }
            } else {
                console.log("WETH/USDC 0.05% pool not found!");
                // Create pool if missing
                pool = factory.createPool(token0, token1, fee);
                // Initialize with approx price (3000 USDC/ETH)
                // WETH is token0 (0x420... < 0x833...)
                // Price = USDC/WETH = 3000 * 1e6 / 1e18 = 3e-9
                // sqrtPriceX96 = sqrt(3e-9) * 2^96 = 4350000000000000000000000 (approx)
                // Let's just use a safe value or skip if too complex. 
                // Mainnet fork SHOULD have this pool.
            }
        }
        
        console.log("All systems deployment complete.");

        // --- 自動更新設定檔 ---
        string memory envPath = "../../packages/ponder/.env.local";
        string memory tsPath = "../../packages/web/src/utils/contracts.ts";

        // 1. 更新 Ponder .env.local
        string memory envContent = string.concat(
            "# Ponder\n",
            "# DATABASE_URL=postgres://postgres:postgres@127.0.0.1:5432/ponder\n\n",
            "# Network\n",
            "PONDER_RPC_URL_31337=http://127.0.0.1:8545\n\n",
            "# Contract Addresses\n",
            "PONDER_POL_TOKEN_ADDRESS=", vm.toString(address(polToken)), "\n",
            "PONDER_POL_TIMELOCK_ADDRESS=", vm.toString(address(timelock)), "\n",
            "PONDER_POL_GOVERNOR_ADDRESS=", vm.toString(address(governor)), "\n",
            "PONDER_POL_STAKING_ADDRESS=", vm.toString(address(polStaking)), "\n",
            "PONDER_TICKET_MARKETPLACE_ADDRESS=", vm.toString(address(marketplace)), "\n",
            "PONDER_MASTER_VAULT_ADDRESS=", vm.toString(address(masterVault)), "\n\n",
            "# Start Block\n",
            "PONDER_START_BLOCK=39760000\n",
            "PONDER_ALPHA_HOOK_ADDRESS=", vm.toString(address(alphaHook)), "\n",
            "PONDER_BATTLE_HOOK_ADDRESS=", vm.toString(address(battleHook)), "\n"
        );
        vm.writeFile(envPath, envContent);
        console.log("Updated Ponder .env.local");

        // 2. 更新 Frontend contracts.ts
        string memory tsContent = string.concat(
            "export const CONTRACTS = {\n",
            "  POLToken: {\n",
            "    address: '", vm.toString(address(polToken)), "',\n",
            "  },\n",
            "  POLTimelock: {\n",
            "    address: '", vm.toString(address(timelock)), "',\n",
            "  },\n",
            "  POLGovernor: {\n",
            "    address: '", vm.toString(address(governor)), "',\n",
            "  },\n",
            "  POLStaking: {\n",
            "    address: '", vm.toString(address(polStaking)), "',\n",
            "  },\n",
            "  TicketMarketplace: {\n",
            "    address: '", vm.toString(address(marketplace)), "',\n",
            "  },\n",
            "  MasterVault: {\n",
            "    address: '", vm.toString(address(masterVault)), "',\n",
            "  },\n",
            "  TicketDescriptor: {\n",
            "    address: '", vm.toString(address(descriptor)), "',\n",
            "  },\n",
            "  AlphaHook: {\n",
            "    address: '", vm.toString(address(alphaHook)), "',\n",
            "  },\n",
            "  BattleHook: {\n",
            "    address: '", vm.toString(address(battleHook)), "',\n",
            "  },\n",
            "  GeneralHook: {\n",
            "    address: '", vm.toString(address(generalHook)), "',\n",
            "  },\n",
            "  ZapRouter: {\n",
            "    address: '", vm.toString(address(zapRouter)), "',\n",
            "  },\n",
            "  QuoterV2: {\n",
            "    address: '0x3d4e44Eb1374240CE5F1B871ab261CD16335B76a',\n",
            "  },\n",
            "  USDC: {\n",
            "    address: '", vm.toString(USDC), "',\n",
            "  }\n",
            "} as const;\n"
        );
        vm.writeFile(tsPath, tsContent);
        console.log("Updated Frontend contracts.ts");

        vm.stopBroadcast();
    }
}