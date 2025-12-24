// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/MasterVault.sol";
import "../src/hooks/AlphaHook.sol";
import "../src/adapters/AaveAdapter.sol";
import "../src/governance/POLStaking.sol";
import "../src/governance/POLToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/mocks/VRFCoordinatorMock.sol";
import "../src/interfaces/IAdapter.sol";

contract MockAdapter is IAdapter {
    IERC20 public asset;
    uint256 public yield;
    
    constructor(address _asset) {
        asset = IERC20(_asset);
    }
    
    function setYield(uint256 _yield) external {
        yield = _yield;
    }
    
    function deposit(uint256 assets, bytes calldata) external override returns (uint256) {
        asset.transferFrom(msg.sender, address(this), assets);
        return assets;
    }
    
    function redeem(uint256 shares, uint256, address receiver, address) external override returns (uint256) {
        asset.transfer(receiver, shares);
        return shares;
    }
    
    function getTotalYield() external view override returns (uint256) {
        return yield;
    }
    
    function reinvestYield(uint256 amount) external override {
        if (amount > yield) yield = 0;
        else yield -= amount;
    }
    
    function collectRevenue(uint256, address) external override {}

    function collectYield(uint256 amount, address receiver) external override {
        require(amount <= yield, "Insufficient yield");
        yield -= amount;
        asset.transfer(receiver, amount);
    }
}

contract AlphaPoolTest is Test {
    MasterVault vault;
    AlphaHook hook;
    MockAdapter adapter;
    VRFCoordinatorMock vrfCoordinator;
    POLToken polToken;
    POLStaking staking;

    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant WHALE = 0x3304e22DdAA22bCdc5fca2269b4180919E639828;

    function setUp() public {
        string memory rpcUrl = vm.envString("BASE_RPC_API_URL");
        vm.createSelectFork(rpcUrl);

        vrfCoordinator = new VRFCoordinatorMock();
        polToken = new POLToken();
        staking = new POLStaking(address(polToken));

        vault = new MasterVault(USDC);
        hook = new AlphaHook(
            address(vault),
            address(vrfCoordinator),
            bytes32(0),
            1,
            address(staking)
        );
        adapter = new MockAdapter(USDC);

        vault.setAdapter(address(hook), address(adapter));
        vault.registerMode(3, address(hook));
    }

    function testLeverageCheck() public {
        uint256 amount = 100 * 1e6;
        deal(USDC, WHALE, amount * 10);

        // 1. Try to deposit without staking -> Should fail (0 staked)
        vm.startPrank(WHALE);
        IERC20(USDC).approve(address(vault), amount * 10);
        
        bytes memory data = abi.encode(uint256(0), uint256(0));
        vm.expectRevert("Leverage cap exceeded");
        vault.deposit(amount, WHALE, 3, data);
        vm.stopPrank();

        // 2. Stake POL
        // Need 25% of TVL. If we deposit 100 USDC, we need 25 POL staked.
        // polToken.mint(WHALE, 25 * 1e18); // POLToken has no mint, transfer from deployer
        polToken.transfer(WHALE, 25 * 1e18);
        vm.startPrank(WHALE);
        polToken.approve(address(staking), 25 * 1e18);
        staking.deposit(25 * 1e18, WHALE);
        
        // Now deposit 100 USDC. TVL=100. Staked=25. 100 <= 25*4. OK.
        vault.deposit(amount, WHALE, 3, data);
        vm.stopPrank();

        // 3. Try to deposit another 100 USDC. TVL=200. Staked=25. 200 > 100. Fail.
        vm.startPrank(WHALE);
        vm.expectRevert("Leverage cap exceeded");
        vault.deposit(amount, WHALE, 3, data);
        vm.stopPrank();
    }

    function testAlphaDrawWithFee() public {
        // Setup Staking to allow deposit
        // polToken.mint(WHALE, 1000 * 1e18);
        polToken.transfer(WHALE, 1000 * 1e18);
        vm.startPrank(WHALE);
        polToken.approve(address(staking), 1000 * 1e18);
        staking.deposit(1000 * 1e18, WHALE);
        vm.stopPrank();

        uint256 amount = 100 * 1e6;
        deal(USDC, WHALE, amount * 2);

        vm.startPrank(WHALE);
        IERC20(USDC).approve(address(vault), amount * 2);

        bytes memory data = abi.encode(uint256(0), uint256(0));
        vault.deposit(amount, WHALE, 3, data);
        vm.stopPrank();

        // Set Governance
        address gov = address(0x999);
        hook.setGovernance(gov);

        // Warp to generate yield in Aave
        vm.warp(block.timestamp + 7 days);
        
        // Simulate Yield generation (Aave on Fork might not generate much in 7 days without activity, 
        // but let's assume it does or we can't test fee easily without mocking Adapter).
        // Actually, Aave Adapter uses real Aave. 
        // Let's check if we have yield.
        uint256 yield = adapter.getTotalYield();
        console.log("Yield generated:", yield);
        
        // If yield is 0, we can't test fee. 
        // Use MockAdapter
        adapter.setYield(100e6);
        deal(USDC, address(adapter), 100e6); // Give it USDC to pay fee
        
        yield = adapter.getTotalYield();
        console.log("Simulated Yield:", yield); // Should be ~100 USDC

        // Draw
        hook.performDraw();
        
        uint256 requestId = 1;
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = 12345;
        
        uint256 govBalanceBefore = IERC20(USDC).balanceOf(gov);
        vrfCoordinator.fulfillRandomWords(requestId, randomWords);
        uint256 govBalanceAfter = IERC20(USDC).balanceOf(gov);

        // Check Fee (20%)
        uint256 fee = govBalanceAfter - govBalanceBefore;
        console.log("Fee collected:", fee);
        
        // Expected fee: 20% of ~100e6 = 20e6
        assertApproxEqAbs(fee, 20e6, 1e4);
    }

    function testRoyalty() public view {
        // Check Royalty Info
        // Sale price = 100 ETH (just for calculation)
        uint256 salePrice = 100 ether;
        
        (address receiver, uint256 royaltyAmount) = vault.royaltyInfo(1, salePrice);
        
        // Receiver should be deployer (this contract in test setup, or msg.sender in constructor)
        // In setUp, vault = new MasterVault(USDC); -> deployer is AlphaPoolTest contract
        assertEq(receiver, address(this));
        
        // Amount should be 2% of 100 ether = 2 ether
        assertEq(royaltyAmount, 2 ether);
        
        console.log("Royalty Receiver:", receiver);
        console.log("Royalty Amount for 100 ETH:", royaltyAmount);
    }
}
