// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/ZapRouter.sol";
import "../src/MasterVault.sol";
import "../src/hooks/AlphaHook.sol";
import "../src/mocks/VRFCoordinatorMock.sol";
import "../src/governance/POLStaking.sol";
import "../src/governance/POLToken.sol";

contract MockSwapRouter is ISwapRouter {
    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut) {
        // Mock swap: 1 ETH -> 3000 USDC
        // amountIn (18 dec) -> amountOut (6 dec)
        // 1e18 -> 3000e6
        // amountOut = amountIn * 3000 / 1e12
        amountOut = (params.amountIn * 3000) / 1e12;
        
        // Transfer USDC to recipient
        IERC20(params.tokenOut).transfer(params.recipient, amountOut);
        
        // Take input (WETH)
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        
        return amountOut;
    }
}

contract ZapRouterTest is Test {
    ZapRouter zap;
    MasterVault vault;
    AlphaHook hook;
    VRFCoordinatorMock vrfCoordinator;
    POLToken polToken;
    POLStaking staking;
    MockSwapRouter mockRouter;

    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    // address constant SWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481; 
    address constant WHALE = 0x3304e22DdAA22bCdc5fca2269b4180919E639828; // USDC Whale

    function setUp() public {
        string memory rpcUrl = vm.envString("BASE_RPC_API_URL");
        vm.createSelectFork(rpcUrl);

        vrfCoordinator = new VRFCoordinatorMock();
        polToken = new POLToken();
        staking = new POLStaking(address(polToken));
        vault = new MasterVault(USDC);
        
        // Setup Hook (Mode 3)
        hook = new AlphaHook(
            address(vault),
            address(vrfCoordinator),
            bytes32(0),
            1,
            address(staking)
        );
        vault.registerMode(3, address(hook));

        mockRouter = new MockSwapRouter();
        // Fund MockRouter with USDC
        deal(USDC, address(mockRouter), 1000000e6);

        zap = new ZapRouter(address(vault), USDC, address(mockRouter), WETH);
    }

    function testZapInETH() public {
        // Stake some POL to pass leverage check
        polToken.transfer(address(this), 1000e18);
        polToken.approve(address(staking), 1000e18);
        staking.deposit(1000e18, address(this));

        uint256 amountIn = 0.01 ether;
        deal(address(this), amountIn);

        bytes memory data = abi.encode(uint256(10), uint256(20)); // x=10, y=20
        
        // Zap In ETH
        // We expect to receive a Ticket NFT
        uint256 tokenId = zap.zapInETH{value: amountIn}(
            0, // minUSDC
            3, // mode
            data, // data
            address(this), // receiver
            3000 // poolFee (0.3%)
        );

        assertGt(tokenId, 0);
        assertEq(vault.ownerOf(tokenId), address(this));
        
        (uint128 assets, , , , , , , ) = vault.tickets(tokenId);
        console.log("Zapped Assets:", assets);
        assertGt(assets, 0);
    }
}
