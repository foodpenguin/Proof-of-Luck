// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/ZapRouter.sol";
import "../src/MasterVault.sol";
import "../src/hooks/GeneralHook.sol";
import "../src/adapters/AaveAdapter.sol";

interface IUniswapV3Pool {
    function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);
    function liquidity() external view returns (uint128);
}

contract ZapRouterForkTest is Test {
    ZapRouter public zapRouter;
    MasterVault public vault;
    IERC20 public USDC = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
    address public WETH = 0x4200000000000000000000000000000000000006;
    address public SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02 on Base

    function setUp() public {
        string memory rpc = vm.envOr("RPC_URL", string("https://base-mainnet.infura.io/v3/3a1f12a726f849158595a467151b4d53"));
        vm.createSelectFork(rpc);
        
        // Deploy Vault
        vault = new MasterVault(address(USDC));
        
        // Deploy Hook & Adapter (Mode 3)
        GeneralHook hook = new GeneralHook(address(vault), address(0), bytes32(0), 0);
        vault.registerMode(3, address(hook));
        
        // Deploy ZapRouter
        zapRouter = new ZapRouter(address(vault), address(USDC), SWAP_ROUTER, WETH);
    }

    function testZapInETH() public {
        uint256 amount = 10 ether; // User used 10 ETH
        uint256 minUSDC = 28272423004; // User's minUSDC
        uint8 mode = 3;
        bytes memory data = abi.encode(uint256(0), uint256(0));
        address receiver = address(this);
        uint24 poolFee = 500; // 0.05% fee tier

        vm.deal(address(this), amount);
        
        // Call zapInETH
        uint256 tokenId = zapRouter.zapInETH{value: amount}(
            minUSDC,
            mode,
            data,
            receiver,
            poolFee
        );

        console.log("Zap successful, Token ID:", tokenId);
        
        // Verify vault balance
        (uint128 principal, , , , , , , ) = vault.tickets(tokenId);
        console.log("Principal:", principal);
        require(principal > 0, "Principal should be > 0");
    }
}
