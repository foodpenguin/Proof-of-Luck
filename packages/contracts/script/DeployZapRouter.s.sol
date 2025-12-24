// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/ZapRouter.sol";

contract DeployZapRouter is Script {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02 on Base

    function run() external {
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }
        
        vm.startBroadcast(deployerPrivateKey);

        address vault = 0xA5fD4A82F2C3C65b1cC76D4fe354A355C0c3af4e;
        
        ZapRouter zapRouter = new ZapRouter(
            vault,
            USDC,
            SWAP_ROUTER,
            WETH
        );
        console.log("ZapRouter deployed at:", address(zapRouter));
        
        vm.stopBroadcast();
    }
}
