// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../src/MasterVault.sol";
import "../src/TicketDescriptor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../src/interfaces/IPOLHook.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("USDC", "USDC") {
        _mint(msg.sender, 1000000 * 1e6);
    }
    
    function decimals() public pure override returns (uint8) {
        return 6;
    }
}

contract MockHook is IPOLHook {
    function beforeDeposit(address, uint256, uint256, bytes calldata) external override {}
    function afterDeposit(address, uint256, uint256, bytes calldata) external override {}
    function onRedeemRequest(address, uint256, bytes calldata) external override {}
    function getRedeemableAmount(uint256, uint256 principal) external pure override returns (uint256) { return principal; }
}

contract DescriptorTest is Test {
    MasterVault vault;
    TicketDescriptor descriptor;
    MockUSDC usdc;
    MockHook hook;
    address user = address(0x1);

    function setUp() public {
        usdc = new MockUSDC();
        vault = new MasterVault(address(usdc));
        descriptor = new TicketDescriptor();
        hook = new MockHook();
        
        vault.registerMode(1, address(hook));
        
        usdc.transfer(user, 1000 * 1e6);
    }

    function testTokenURI() public {
        // 1. Set descriptor
        vault.setDescriptor(address(descriptor));

        // 2. Mint a ticket
        vm.startPrank(user);
        usdc.approve(address(vault), 100 * 1e6);
        
        bytes memory data = abi.encode(uint256(50), uint256(60)); // x=50, y=60
        uint256 tokenId = vault.deposit(100 * 1e6, user, 1, data);
        vm.stopPrank();

        // 3. Check URI
        string memory uri = vault.tokenURI(tokenId);
        assertTrue(bytes(uri).length > 0);
        
        // Basic check for data URI prefix
        assertEq(substring(uri, 0, 29), "data:application/json;base64,");
    }

    function testTokenURIFailsWithoutDescriptor() public {
        // 1. Mint a ticket (descriptor not set yet)
        vm.startPrank(user);
        usdc.approve(address(vault), 100 * 1e6);
        
        bytes memory data = abi.encode(uint256(50), uint256(60));
        uint256 tokenId = vault.deposit(100 * 1e6, user, 1, data);
        vm.stopPrank();

        // 2. Check URI reverts
        vm.expectRevert("Descriptor not set");
        vault.tokenURI(tokenId);
    }
    
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for(uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }
}
