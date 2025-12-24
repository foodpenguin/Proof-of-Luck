// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/hooks/AlphaHook.sol";

contract AutoDraw is Script {
    function run() external {
        uint256 deployerPrivateKey;
        try vm.envUint("PRIVATE_KEY") returns (uint256 key) {
            deployerPrivateKey = key;
        } catch {
            deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        }

        vm.startBroadcast(deployerPrivateKey);

        // AlphaHook address from CONTRACTS
        AlphaHook hook = AlphaHook(0x0C7074e8893767BAcF9A7E4400e076106719dE33);
        
        console.log("Attempting to trigger draw on AlphaHook:", address(hook));

        try hook.draw() {
            console.log("Draw triggered successfully");
        } catch Error(string memory reason) {
            console.log("Draw failed:", reason);
        } catch {
            console.log("Draw failed with unknown error");
        }

        vm.stopBroadcast();
    }
}
