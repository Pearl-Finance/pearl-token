// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@tangible/layerzero/lzApp/LzAppUpgradeable.sol";

import "../src/PearlMigrator.sol";

contract PearlMigratorTest is Test {
    PearlMigrator migrator;

    address lzEndpointAddress = makeAddr("lzEndpoint");
    address pearlAddress = makeAddr("pearl");
    address votingEscrowAddress = makeAddr("votingEscrow");
    address legacyPearlAddress = makeAddr("legacyPearl");
    address legacyVEPearlAddress = makeAddr("legacyVEPearl");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    event Migrate(address indexed from, address indexed to, uint256 amount);
    event MigrateVE(address indexed from, address indexed to, uint256 tokenId);
    event MessageFailed(uint16 srcChainId, bytes srcAddress, uint64 nonce, bytes payload, bytes reason);

    function setUp() public {
        migrator = new PearlMigrator(lzEndpointAddress, legacyPearlAddress, legacyVEPearlAddress, 101);
        bytes memory init = abi.encodeCall(migrator.initialize, ());
        ERC1967Proxy migratorProxy = new ERC1967Proxy(address(migrator), init);

        migrator = PearlMigrator(address(migratorProxy));

        migrator.setMinDstGas(101, 0, 200_000);
        migrator.setMinDstGas(101, 1, 1_000_000);

        migrator.setTrustedRemote(101, abi.encodePacked(pearlAddress, address(migrator)));
    }

    function test_init() public {
        vm.expectRevert(PearlMigrator.InvalidZeroAddress.selector);
        new PearlMigrator(address(0), address(1), address(1), 1);

        vm.expectRevert(PearlMigrator.InvalidZeroAddress.selector);
        new PearlMigrator(address(1), address(0), address(1), 1);

        vm.expectRevert(PearlMigrator.InvalidZeroAddress.selector);
        new PearlMigrator(address(1), address(1), address(0), 1);
    }

    function test_migrate() public {
        vm.startPrank(alice);

        uint256 amount = 1e18;
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200_000));

        vm.mockCall(legacyPearlAddress, abi.encodeCall(IERC20.balanceOf, (alice)), abi.encode(amount));
        vm.mockCall(legacyPearlAddress, abi.encodeCall(ERC20Burnable.burnFrom, (alice, amount)), "");
        vm.mockCall(lzEndpointAddress, abi.encodeWithSelector(ILayerZeroEndpoint.send.selector), "");

        vm.expectEmit();
        emit Migrate(alice, bob, amount);
        migrator.migrate(bob, payable(address(0)), address(0), adapterParams);
    }

    function test_migrateVotingEscrow() public {
        vm.startPrank(alice);

        uint256 tokenId = 1;
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(1_000_000));

        vm.mockCall(legacyVEPearlAddress, abi.encodeCall(IERC721.transferFrom, (alice, address(migrator), tokenId)), "");
        vm.mockCall(legacyVEPearlAddress, abi.encodeCall(ILegacyVotingEscrow.locked, (tokenId)), abi.encode(100, 200));
        vm.mockCall(lzEndpointAddress, abi.encodeWithSelector(ILayerZeroEndpoint.send.selector), "");

        vm.expectEmit();
        emit MigrateVE(alice, bob, tokenId);
        migrator.migrateVotingEscrow(tokenId, bob, payable(address(0)), address(0), adapterParams);
    }

    function test_migrateVotingEscrowError() public {
        vm.startPrank(alice);

        uint256 tokenId = 1;
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(1_000_000));

        vm.mockCall(legacyVEPearlAddress, abi.encodeCall(IERC721.transferFrom, (alice, address(migrator), tokenId)), "");
        vm.mockCall(legacyVEPearlAddress, abi.encodeCall(ILegacyVotingEscrow.locked, (tokenId)), abi.encode(0, 0));

        vm.expectRevert(abi.encodeWithSelector(PearlMigrator.NonPositiveLockedAmount.selector, 0));
        migrator.migrateVotingEscrow(tokenId, bob, payable(address(0)), address(0), adapterParams);

        skip(10);

        vm.mockCall(legacyVEPearlAddress, abi.encodeCall(ILegacyVotingEscrow.locked, (tokenId)), abi.encode(10, 10));

        vm.expectRevert(abi.encodeWithSelector(PearlMigrator.LockExpired.selector, 10));
        migrator.migrateVotingEscrow(tokenId, bob, payable(address(0)), address(0), adapterParams);
    }

    function test_estimateMigrateFee() public {
        uint256 amount = 1e18;
        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(200_000));
        bytes memory payload = abi.encode(0, abi.encodePacked(bob), amount);

        vm.mockCall(
            lzEndpointAddress,
            abi.encodeCall(ILayerZeroEndpoint.estimateFees, (101, address(migrator), payload, false, adapterParams)),
            abi.encode(10, 0)
        );
        (uint256 nativeFee, uint256 zroFee) =
            migrator.estimateMigrateFee(101, abi.encodePacked(bob), amount, false, adapterParams);

        assertEq(nativeFee, 10);
        assertEq(zroFee, 0);
    }

    function test_estimateMigrateVotingEscrowFee() public {
        uint256 amount = 1e18;
        uint256 duration = 1 weeks;

        bytes memory adapterParams = abi.encodePacked(uint16(1), uint256(1_000_000));
        bytes memory payload = abi.encode(1, abi.encodePacked(bob), amount, duration);

        vm.mockCall(
            lzEndpointAddress,
            abi.encodeCall(ILayerZeroEndpoint.estimateFees, (101, address(migrator), payload, false, adapterParams)),
            abi.encode(20, 0)
        );
        (uint256 nativeFee, uint256 zroFee) =
            migrator.estimateMigrateVotingEscrowFee(101, abi.encodePacked(bob), amount, duration, false, adapterParams);

        assertEq(nativeFee, 20);
        assertEq(zroFee, 0);
    }

    function test_receiveError() public {
        vm.prank(lzEndpointAddress);
        vm.expectEmit(false, false, false, false);

        emit MessageFailed(101, abi.encodePacked(pearlAddress, address(migrator)), 1, "", "");
        migrator.lzReceive(101, abi.encodePacked(pearlAddress, address(migrator)), 1, "");
    }
}
