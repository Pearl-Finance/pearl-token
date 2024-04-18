// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@tangible/layerzero/lzApp/LzAppUpgradeable.sol";

import "../src/token/Pearl.sol";

contract PearlTest is Test {
    Pearl pearl;
    Pearl pearlImpl;
    Pearl satellitePearl;
    Pearl satellitePearlImpl;

    address lzEndpointAddress = makeAddr("lzEndpoint");
    address votingEscrowAddress = makeAddr("votingEscrow");

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        vm.mockCall(lzEndpointAddress, abi.encodeWithSelector(ILayerZeroEndpoint.send.selector), "");
        vm.mockCall(votingEscrowAddress, abi.encodeWithSelector(IVotingEscrow.mint.selector), abi.encode(1));

        pearlImpl = new Pearl(block.chainid, lzEndpointAddress);
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (votingEscrowAddress));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        pearl = Pearl(address(pearlProxy));

        satellitePearlImpl = new Pearl(block.chainid + 1, lzEndpointAddress);
        init = abi.encodeCall(pearlImpl.initialize, (votingEscrowAddress));
        pearlProxy = new ERC1967Proxy(address(satellitePearlImpl), init);

        satellitePearl = Pearl(address(pearlProxy));
    }

    function test_init() public {
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (address(0)));
        vm.expectRevert(Pearl.InvalidZeroAddress.selector);
        new ERC1967Proxy(address(pearlImpl), init);
    }

    function test_setMinter() public {
        address minter1 = address(1);
        address minter2 = address(2);

        Vm.Log[] memory logs;

        vm.recordLogs();

        pearl.setMinter(minter1);
        assertEq(pearl.minter(), minter1);

        logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], keccak256("MinterUpdated(address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(1)));

        pearl.setMinter(minter2);
        assertEq(pearl.minter(), minter2);

        logs = vm.getRecordedLogs();
        assertEq(logs[0].topics[0], keccak256("MinterUpdated(address)"));
        assertEq(logs[0].topics[1], bytes32(uint256(2)));

        vm.expectRevert(Pearl.ValueUnchanged.selector);
        pearl.setMinter(minter2);
    }

    function test_mint() public {
        pearl.setMinter(alice);
        satellitePearl.setMinter(alice);

        vm.expectRevert(abi.encodeWithSelector(Pearl.NotAuthorized.selector, address(this)));
        pearl.mint(address(this), 100e18);

        vm.startPrank(alice);
        pearl.mint(address(this), 100e18);

        vm.expectRevert(abi.encodeWithSelector(Pearl.UnsupportedChain.selector, block.chainid));
        satellitePearl.mint(address(this), 100e18);
    }

    function test_burn() public {
        pearl.setMinter(alice);

        vm.prank(alice);
        pearl.mint(address(this), 100e18);

        pearl.burn(50e18);

        assertEq(pearl.balanceOf(address(this)), 50e18);

        vm.prank(bob);
        vm.expectRevert();
        pearl.burnFrom(address(this), 50e18);

        pearl.approve(bob, 50e18);

        vm.prank(bob);
        pearl.burnFrom(address(this), 50e18);
    }

    function test_crossChainTransfer() public {
        pearl.setMinter(alice);
        pearl.setTrustedRemoteAddress(102, abi.encodePacked(address(pearl)));

        vm.prank(alice);
        pearl.mint(address(this), 100e18);

        vm.expectCall(lzEndpointAddress, abi.encodeWithSelector(ILayerZeroEndpoint.send.selector));
        pearl.sendFrom(address(this), 102, abi.encodePacked(address(this)), 100e18, payable(address(0)), address(0), "");

        vm.prank(lzEndpointAddress);
        vm.expectCall(
            bob,
            abi.encodeWithSignature(
                "notifyCredit(uint16,address,address,address,uint256)", 102, bob, bob, address(pearl), 100e18
            )
        );
        pearl.lzReceive(
            102,
            abi.encodePacked(address(pearl), address(pearl)),
            1,
            abi.encode(0, bob, bob, abi.encodePacked(bob), 100e18)
        );

        vm.prank(lzEndpointAddress);
        vm.expectCall(votingEscrowAddress, abi.encodeWithSelector(IVotingEscrow.mint.selector, bob, 100e18, 10 weeks));
        pearl.lzReceive(
            102,
            abi.encodePacked(address(pearl), address(pearl)),
            1,
            abi.encode(1, abi.encodePacked(bob), 1, 100e18, 10 weeks)
        );
    }
}
