# 設定專案根路徑 (請確認此路徑正確)
$RootPath = "D:\penguin_data\code\ProofOfLuck"
$ContractPath = "$RootPath\packages\contracts"
$PonderPath = "$RootPath\packages\ponder"
$WebPath = "$RootPath\packages\web"

# --- 1. 啟動 Anvil (視窗 1) ---
Write-Host "正在啟動 Anvil Fork..." -ForegroundColor Cyan
# 使用固定的 block number 可以讓測試環境更穩定
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd `"$ContractPath`"; anvil --fork-url https://mainnet.base.org --fork-block-number 39760000 --chain-id 31337 --block-time 10 --allow-origin '*' --order fifo --auto-impersonate --host 0.0.0.0"

# 等待 Anvil 完全啟動
Start-Sleep -Seconds 20

# --- 2. 執行部署與代幣注入 (視窗 2) ---
Write-Host "正在執行合約部署與代幣注入..." -ForegroundColor Yellow
$SetupCommands = @"
cd `"$ContractPath`";

Write-Host '--- Step 1: Setting Whale Balances (ETH) ---' -ForegroundColor Magenta;
cast rpc anvil_setBalance 0xd0b53D9277642d899DF5C87A3966A349A798F224 0x8AC7230489E80000 --rpc-url http://10.189.163.121:8545;
cast rpc anvil_setBalance 0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4 0x8AC7230489E80000 --rpc-url http://10.189.163.121:8545;
cast rpc anvil_setBalance 0x501CEd8dFeC4Dcb6836b7BC0241AB1C3a93Ec434 0x8AC7230489E80000 --rpc-url http://10.189.163.121:8545;

Write-Host '--- Step 2: Funding Account (ERC20) ---' -ForegroundColor Magenta;
# 已修正為 Checksum 地址防止編譯錯誤
forge script script/FundAccount.s.sol --sig 'fundAll(address,uint256)' 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 5000000 --rpc-url http://10.189.163.121:8545 --broadcast --unlocked;

Write-Host '--- Step 3: Deploying Contracts ---' -ForegroundColor Magenta;
forge script script/DeployFork.s.sol --rpc-url http://10.189.163.121:8545 --broadcast --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

Write-Host 'Setup Complete!' -ForegroundColor Green;
"@
Start-Process powershell -ArgumentList "-NoExit", "-Command", $SetupCommands

# 等待部署完成後再啟動 Ponder，確保 Ponder 能抓到剛部署好的合約
Write-Host "等待部署完成 (60s)..." -ForegroundColor Gray
Start-Sleep -Seconds 85

# --- 3. 啟動 Ponder (視窗 3) ---
Write-Host "正在清理並啟動 Ponder..." -ForegroundColor Blue
# 加入 rm -rf .ponder 的 PowerShell 等效指令
$PonderCommands = @"
cd `"$PonderPath`";
Write-Host 'Cleaning Ponder cache...' -ForegroundColor Gray;
if (Test-Path .ponder) { Remove-Item -Recurse -Force .ponder };
npm run dev
"@
Start-Process powershell -ArgumentList "-NoExit", "-Command", $PonderCommands

# --- 4. 啟動 Web (視窗 4) ---
Write-Host "正在啟動 Web 前端..." -ForegroundColor Green
Start-Process powershell -ArgumentList "-NoExit", "-Command", "cd `"$WebPath`"; npm run start -- --host"

Write-Host "所有視窗已開啟。請檢查各視窗 Log。" -ForegroundColor White