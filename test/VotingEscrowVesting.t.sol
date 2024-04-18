// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/interfaces/IERC6372.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/token/Pearl.sol";
import "../src/governance/VotingEscrow.sol";
import "../src/governance/VotingEscrowVesting.sol";

contract MisalignedVE is IERC6372 {
    function clock() public view virtual override returns (uint48) {
        return uint48(block.number);
    }

    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=blocknumber&from=default";
    }
}

contract VotingEscrowVestingTest is Test {
    Pearl pearl;
    VotingEscrow vePearl;
    VotingEscrowVesting vesting;
    IVoter voter;

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        address voterAddress = makeAddr("voter");
        voter = IVoter(voterAddress);

        vm.mockCall(voterAddress, abi.encodeWithSelector(IVoter.poke.selector), "");

        address votingEscrowProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 3);
        address vestingAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 4);

        Pearl pearlImpl = new Pearl(block.chainid, address(1));
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (votingEscrowProxyAddress));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));
        init = abi.encodeCall(votingEscrowImpl.initialize, (vestingAddress, address(voter), address(1)));
        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrowImpl), init);

        console.log("VE: %s / %s", votingEscrowProxyAddress, address(votingEscrowProxy));
        console.log("ves: %s", vestingAddress);

        vesting = new VotingEscrowVesting(address(votingEscrowProxy));

        pearl = Pearl(address(pearlProxy));
        vePearl = VotingEscrow(address(votingEscrowProxy));

        pearl.mint(address(this), 100e18);
    }

    function test_init() public {
        vm.expectRevert(VotingEscrowVesting.InvalidZeroAddress.selector);
        new VotingEscrowVesting(address(0));

        IERC6372 misalignedVE = new MisalignedVE();

        vm.expectRevert(VotingEscrowVesting.ClockMisalignment.selector);
        new VotingEscrowVesting(address(misalignedVE));
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

        vesting.withdraw(address(this), tokenId);

        schedule = vesting.getSchedule(tokenId);
        assertEq(schedule.startTime, 0);
        assertEq(schedule.endTime, 0);
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
        pearl.approve(address(vePearl), 2e18);

        uint256 tokenId1 = vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        uint256 tokenId2 = vePearl.mint(bob, 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId1);
        vesting.deposit(tokenId1);

        vm.startPrank(bob);
        vePearl.approve(address(vesting), tokenId2);
        vesting.deposit(tokenId2);
        vm.stopPrank();

        assertEq(vePearl.getVotes(address(this)), 0);
        assertEq(vePearl.getVotes(address(vesting)), 0);

        vm.warp(block.timestamp + 52 weeks);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.VestingNotFinished.selector));
        vesting.claim(address(this), tokenId1);

        vesting.withdraw(address(this), tokenId1);

        assertEq(vePearl.getVotes(address(this)), 0.5e18);
        assertEq(vePearl.getLockedAmount(tokenId1), 1e18);

        vePearl.approve(address(vesting), tokenId1);
        vesting.deposit(tokenId1);

        vm.warp(block.timestamp + 52 weeks);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.NotAuthorized.selector, alice));
        vesting.claim(address(this), tokenId1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.NotAuthorized.selector, bob));
        vesting.claim(address(this), tokenId1);

        vesting.claim(address(this), tokenId1);
        assertEq(pearl.balanceOf(address(this)), 99e18);
    }

    function test_withdraw() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.NotAuthorized.selector, alice));
        vesting.withdraw(address(this), tokenId);

        vm.expectCall(address(vePearl), abi.encodeCall(vePearl.updateVestingDuration, (tokenId, 2 * 52 weeks)));
        vesting.withdraw(address(this), tokenId);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        skip(2 * 52 weeks);

        vm.mockCallRevert(
            address(vePearl),
            abi.encodeWithSelector(VotingEscrow.updateVestingDuration.selector),
            "SHOULD_NOT_BE_CALLED"
        );
        vesting.withdraw(address(this), tokenId);
    }
}
