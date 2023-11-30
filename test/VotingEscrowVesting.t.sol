// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/token/Pearl.sol";
import "../src/governance/VotingEscrow.sol";
import "../src/governance/VotingEscrowVesting.sol";

import "./mocks/MockVoter.sol";

contract VotingEscrowTest is Test {
    Pearl pearl;
    VotingEscrow vePearl;
    VotingEscrowVesting vesting;
    IVoter voter;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        voter = new MockVoter();

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        Pearl pearlImpl = new Pearl(block.chainid, address(0));
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (votingEscrowProxyAddress));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        vesting = new VotingEscrowVesting(votingEscrowProxyAddress);

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));
        init = abi.encodeCall(votingEscrowImpl.initialize, (address(vesting), address(voter), address(0)));
        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrowImpl), init);

        pearl = Pearl(address(pearlProxy));
        vePearl = VotingEscrow(address(votingEscrowProxy));

        pearl.mint(address(this), 100e18);
    }

    function test_initials() public {
        assertEq(address(vesting.votingEscrow()), address(vePearl));
        assertEq(vesting.clock(), block.timestamp);
        assertEq(keccak256(abi.encodePacked(vesting.CLOCK_MODE())), keccak256(abi.encodePacked("mode=timestamp")));
    }

    function test_balanceOf() public {
        pearl.approve(address(vePearl), 3e18);

        uint256 tokenId1 = vePearl.mint(address(this), 1e18, 52 weeks);
        uint256 tokenId2 = vePearl.mint(address(this), 1e18, 52 weeks);
        uint256 tokenId3 = vePearl.mint(address(this), 1e18, 52 weeks);

        assertEq(vesting.balanceOf(address(this)), 0);

        vePearl.approve(address(vesting), tokenId1);
        vesting.deposit(tokenId1);
        assertEq(vesting.balanceOf(address(this)), 1);

        vePearl.approve(address(vesting), tokenId2);
        vesting.deposit(tokenId2);
        assertEq(vesting.balanceOf(address(this)), 2);

        vePearl.approve(address(vesting), tokenId3);
        vesting.deposit(tokenId3);
        assertEq(vesting.balanceOf(address(this)), 3);

        vesting.withdraw(address(this), tokenId1);
        assertEq(vesting.balanceOf(address(this)), 2);

        vesting.withdraw(address(this), tokenId2);
        assertEq(vesting.balanceOf(address(this)), 1);

        vesting.withdraw(address(this), tokenId3);
        assertEq(vesting.balanceOf(address(this)), 0);
    }

    function test_getSchedule() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        VotingEscrowVesting.VestingSchedule memory schedule = vesting.getSchedule(tokenId);
        assertEq(schedule.startTime, block.timestamp);
        assertEq(schedule.endTime, block.timestamp + 52 weeks);
        assertEq(schedule.amount, 1e18);

        vesting.withdraw(address(this), tokenId);

        schedule = vesting.getSchedule(tokenId);
        assertEq(schedule.startTime, 0);
        assertEq(schedule.endTime, 0);
        assertEq(schedule.amount, 0);
    }

    function test_tokenOfDepositorByIndex() public {
        pearl.approve(address(vePearl), 3e18);

        uint256 tokenId1 = vePearl.mint(address(this), 1e18, 52 weeks);
        uint256 tokenId2 = vePearl.mint(address(this), 1e18, 52 weeks);
        uint256 tokenId3 = vePearl.mint(address(this), 1e18, 52 weeks);

        vePearl.approve(address(vesting), tokenId1);
        vesting.deposit(tokenId1);

        vePearl.approve(address(vesting), tokenId2);
        vesting.deposit(tokenId2);

        vePearl.approve(address(vesting), tokenId3);
        vesting.deposit(tokenId3);

        assertEq(vesting.tokenOfDepositorByIndex(address(this), 0), tokenId1);
        assertEq(vesting.tokenOfDepositorByIndex(address(this), 1), tokenId2);
        assertEq(vesting.tokenOfDepositorByIndex(address(this), 2), tokenId3);

        vesting.withdraw(address(this), tokenId1);

        assertEq(vesting.tokenOfDepositorByIndex(address(this), 0), tokenId3);
        assertEq(vesting.tokenOfDepositorByIndex(address(this), 1), tokenId2);

        vesting.withdraw(address(this), tokenId2);

        assertEq(vesting.tokenOfDepositorByIndex(address(this), 0), tokenId3);

        vesting.withdraw(address(this), tokenId3);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.OutOfBoundsIndex.selector, address(this), 0));
        vesting.tokenOfDepositorByIndex(address(this), 0);
    }

    function test_vesting() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        assertEq(vePearl.getVotes(address(this)), 0);
        assertEq(vePearl.getVotes(address(vesting)), 0);

        vm.warp(block.timestamp + 52 weeks);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.VestingNotFinished.selector));
        vesting.claim(address(this), tokenId);

        vesting.withdraw(address(this), tokenId);

        assertEq(vePearl.getVotes(address(this)), 0.5e18);
        assertEq(vePearl.getLockedAmount(tokenId), 1e18);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        vm.warp(block.timestamp + 52 weeks);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.NotAuthorized.selector, alice));
        vesting.claim(address(this), tokenId);

        vesting.claim(address(this), tokenId);
        assertEq(pearl.balanceOf(address(this)), 100e18);
    }

    function test_withdraw() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.NotAuthorized.selector, alice));
        vesting.withdraw(address(this), tokenId);
    }
}
