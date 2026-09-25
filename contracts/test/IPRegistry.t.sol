// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/IPRegistry.sol";

contract IPRegistryTest is Test {
    IPRegistry registry;

    address creator = address(0xC1);
    address agent = address(0xA1);
    address stranger = address(0xB2);

    string constant CID = "bafybeigdyrztest0000000000000000000000000000000000000000000000";
    uint256 constant PRICE = 0.01 ether;

    function setUp() public {
        registry = new IPRegistry();
        vm.deal(agent, 1 ether);
        vm.deal(stranger, 1 ether);
    }

    function _mint() internal returns (uint256 assetId) {
        vm.prank(creator);
        assetId = registry.mintIP(CID, PRICE);
    }

    // ---- Minting -----------------------------------------------------

    function test_MintSetsOwnerCidAndPrice() public {
        uint256 assetId = _mint();

        assertEq(registry.ownerOf(assetId), creator);
        assertEq(registry.cidOf(assetId), CID);
        assertEq(registry.priceOf(assetId), PRICE);
        assertEq(registry.licenserOf(assetId), creator);
    }

    function test_MintEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IPRegistry.IPMinted(0, creator, CID, PRICE);
        vm.prank(creator);
        registry.mintIP(CID, PRICE);
    }

    // ---- Access --------------------------------------------------------

    function test_NoAccessBeforePayment() public {
        uint256 assetId = _mint();
        assertFalse(registry.hasActiveAccess(assetId, agent));
    }

    function test_RequestAccessRevertsOnInsufficientPayment() public {
        uint256 assetId = _mint();
        vm.prank(agent);
        vm.expectRevert("IPRegistry: insufficient payment");
        registry.requestAccess{value: PRICE - 1}(assetId);
    }

    function test_AccessGrantedAfterPayment() public {
        uint256 assetId = _mint();

        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);

        assertTrue(registry.hasActiveAccess(assetId, agent));
        // stranger who didn't pay still has no access
        assertFalse(registry.hasActiveAccess(assetId, stranger));
    }

    function test_AccessExpiresAfterWindow() public {
        uint256 assetId = _mint();

        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);
        assertTrue(registry.hasActiveAccess(assetId, agent));

        vm.warp(block.timestamp + registry.ACCESS_WINDOW() + 1);
        assertFalse(registry.hasActiveAccess(assetId, agent));
    }

    function test_LicenserCanRevokeEarly() public {
        uint256 assetId = _mint();

        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);
        assertTrue(registry.hasActiveAccess(assetId, agent));

        vm.prank(creator);
        registry.revokeAccess(assetId, agent);
        assertFalse(registry.hasActiveAccess(assetId, agent));
    }

    function test_NonLicenserCannotRevoke() public {
        uint256 assetId = _mint();
        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);

        vm.prank(stranger);
        vm.expectRevert("IPRegistry: not licenser");
        registry.revokeAccess(assetId, agent);
    }

    // ---- Withdrawals -----------------------------------------------------

    function test_LicenserCanWithdrawEscrow() public {
        uint256 assetId = _mint();
        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);

        uint256 before = creator.balance;
        vm.prank(creator);
        registry.withdraw(assetId);
        assertEq(creator.balance, before + PRICE);
    }

    function test_NonLicenserCannotWithdraw() public {
        uint256 assetId = _mint();
        vm.prank(agent);
        registry.requestAccess{value: PRICE}(assetId);

        vm.prank(stranger);
        vm.expectRevert("IPRegistry: not licenser");
        registry.withdraw(assetId);
    }

    function test_RequestAccessOnNonexistentAssetReverts() public {
        vm.prank(agent);
        vm.expectRevert("IPRegistry: asset does not exist");
        registry.requestAccess{value: PRICE}(999);
    }
}
