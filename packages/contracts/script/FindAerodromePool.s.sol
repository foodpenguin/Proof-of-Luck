// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";

interface IPoolFactory {
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);
}

interface IVoter {
    function gauges(address pool) external view returns (address);
}

contract FindAerodromePool is Script {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant USDbC = 0xd9aAEc86B65D86f6A7B5B1b0c42FFA531710b6CA;
    address constant POOL_FACTORY = 0x420DD381b31aEf6683db6B902084cB0FFECe40Da;
    address constant VOTER = 0x16613524e02ad97eDfeF371bC883F2F5d6C480A5;

    function run() external view {
        IPoolFactory factory = IPoolFactory(POOL_FACTORY);
        IVoter voter = IVoter(VOTER);

        // Check Stable Pool
        address stablePool = factory.getPool(USDC, USDbC, true);
        console.log("USDC/USDbC Stable Pool Address:", stablePool);

        if (stablePool != address(0)) {
            address gauge = voter.gauges(stablePool);
            console.log("USDC/USDbC Stable Pool Gauge Address:", gauge);
        } else {
            console.log("No Stable Pool found.");
        }

        // Check Volatile Pool (just in case)
        address volatilePool = factory.getPool(USDC, USDbC, false);
        console.log("USDC/USDbC Volatile Pool Address:", volatilePool);
        
        if (volatilePool != address(0)) {
             address gauge = voter.gauges(volatilePool);
             console.log("USDC/USDbC Volatile Pool Gauge Address:", gauge);
        }
    }
}
