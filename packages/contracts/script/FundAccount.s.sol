// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract FundAccount is Script {
    struct TokenInfo {
        address token;
        address whale;
    }
    
    TokenInfo[] public tokens;

    function setUp() public {
        // 設定代幣與大戶地址 (Base Mainnet Fork)
        // USDC
        tokens.push(TokenInfo(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913, 0xd0b53D9277642d899DF5C87A3966A349A798F224));
        // AERO
        tokens.push(TokenInfo(0x940181a94A35A4569E4529A3CDfB74e38FD98631, 0xeBf418Fe2512e7E6bd9b87a8F0f294aCDC67e6B4));
        // VIRTUAL
        tokens.push(TokenInfo(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b, 0x501CEd8dFeC4Dcb6836b7BC0241AB1C3a93Ec434));
    }

    function run() external {
        // 預設目標地址改為 Checksum 版本避免編譯錯誤
        address to = vm.envOr("TO", address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266));
        uint256 amount = vm.envOr("AMOUNT", uint256(1000000));

        fundAll(to, amount);
    }

    function fundAll(address to, uint256 amount) public {
        for (uint i = 0; i < tokens.length; i++) {
            _fundToken(tokens[i], to, amount);
        }
    }

    function _fundToken(TokenInfo memory info, address to, uint256 amount) internal {
        try IERC20Metadata(info.token).decimals() returns (uint8 decimals) {
            uint256 rawAmount = amount * (10 ** decimals);
            string memory symbol = IERC20Metadata(info.token).symbol();
            
            // 在 Anvil Fork 中，這步驟會強制修改節點狀態
            vm.deal(info.whale, 1 ether);

            // 使用 startBroadcast 而不是 prank
            // 配合 --unlocked 參數，Forge 會要求 Anvil 節點直接執行此帳戶的交易
            vm.startBroadcast(info.whale);
            IERC20Metadata(info.token).transfer(to, rawAmount);
            vm.stopBroadcast();

            console.log("Successfully sent %s %s to %s", amount, symbol, to);
        } catch {
            console.log("Error: Failed to process token at address %s", info.token);
        }
    }
}