// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "../src/token/Pearl.sol";
import "../src/governance/VotingEscrow.sol";
import "../src/governance/VotingEscrowVesting.sol";
import "../src/ui/VotingEscrowArtProxy.sol";

contract VotingEscrowTest is Test {
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
        address artProxyAddress = vm.computeCreateAddress(address(this), vm.getNonce(address(this)) + 5);

        Pearl pearlImpl = new Pearl(block.chainid, address(1));
        bytes memory init = abi.encodeCall(pearlImpl.initialize, (votingEscrowProxyAddress));
        ERC1967Proxy pearlProxy = new ERC1967Proxy(address(pearlImpl), init);

        VotingEscrow votingEscrowImpl = new VotingEscrow(address(pearlProxy));
        init = abi.encodeCall(votingEscrowImpl.initialize, (vestingAddress, address(voter), artProxyAddress));
        ERC1967Proxy votingEscrowProxy = new ERC1967Proxy(address(votingEscrowImpl), init);

        vesting = new VotingEscrowVesting(address(votingEscrowProxy));

        new VotingEscrowArtProxy();

        pearl = Pearl(address(pearlProxy));
        vePearl = VotingEscrow(address(votingEscrowProxy));

        pearl.mint(address(this), 100e18);
        pearl.transfer(bob, 1e18);

        vm.prank(bob);
        pearl.transfer(address(this), 1e18);
    }

    function test_invalidInitialization() public {
        ERC1967Proxy votingEscrowProxy;
        VotingEscrow votingEscrowImpl = new VotingEscrow(address(1));

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        votingEscrowProxy = new ERC1967Proxy(
            address(votingEscrowImpl), abi.encodeCall(votingEscrowImpl.initialize, (address(0), address(1), address(1)))
        );

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        votingEscrowProxy = new ERC1967Proxy(
            address(votingEscrowImpl), abi.encodeCall(votingEscrowImpl.initialize, (address(1), address(0), address(1)))
        );

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        votingEscrowProxy = new ERC1967Proxy(
            address(votingEscrowImpl), abi.encodeCall(votingEscrowImpl.initialize, (address(1), address(1), address(0)))
        );
    }

    function test_initials() public {
        assertEq(address(vePearl.lockedToken()), address(pearl));
        assertEq(vePearl.vestingContract(), address(vesting));
        assertEq(vePearl.clock(), block.timestamp);
        assertEq(keccak256(abi.encodePacked(vePearl.CLOCK_MODE())), keccak256(abi.encodePacked("mode=timestamp")));
    }

    function test_setters() public {
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        vePearl.setArtProxy(address(0));

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        vePearl.setVestingContract(address(0));

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidZeroAddress.selector));
        vePearl.setVoter(address(0));

        vePearl.setArtProxy(address(1));
        assertEq(vePearl.artProxy(), address(1));

        vePearl.setVestingContract(address(2));
        assertEq(vePearl.vestingContract(), address(2));

        vePearl.setVoter(address(3));
        assertEq(vePearl.voter(), address(3));
    }

    function test_mint() public {
        pearl.approve(address(vePearl), 3e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        assertEq(vePearl.getLockedAmount(tokenId), 1e18);
        assertEq(vePearl.getRemainingVestingDuration(tokenId), 2 * 52 weeks);
        assertEq(vePearl.getVotes(address(this)), 1e18);
        assertEq(vePearl.getMintingTimestamp(tokenId), block.timestamp);

        vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        assertEq(vePearl.getVotes(address(this)), 2e18);

        vePearl.mint(address(this), 1e18, 52 weeks);
        assertEq(vePearl.getVotes(address(this)), 2.5e18);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.ZeroLockBalance.selector));
        vePearl.mint(address(this), 0, 52 weeks);

        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrow.InvalidVestingDuration.selector, 7 days, 2 weeks, 104 weeks)
        );
        vePearl.mint(address(this), 1e18, 7 days);

        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrow.InvalidVestingDuration.selector, 200 weeks, 2 weeks, 104 weeks)
        );
        vePearl.mint(address(this), 1e18, 200 weeks);

        pearl.transfer(address(pearl), 10);

        vm.startPrank(address(pearl));
        pearl.approve(address(vePearl), 10);
        vePearl.mint(address(this), 5, 1 days);
        vePearl.mint(address(this), 5, 200 weeks);
    }

    function test_delegate() public {
        pearl.approve(address(vePearl), 3e18);

        vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        vePearl.mint(address(this), 1e18, 1 * 52 weeks);

        assertEq(vePearl.getVotes(address(this)), 2.5e18);
        assertEq(vePearl.getVotes(alice), 0);

        vePearl.delegate(alice);

        assertEq(vePearl.getVotes(address(this)), 0);
        assertEq(vePearl.getVotes(alice), 2.5e18);
    }

    function test_depositFor() public {
        pearl.approve(address(vePearl), 3e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.depositFor(tokenId, 1e18);

        assertEq(vePearl.getVotes(address(this)), 2e18);
        assertEq(vePearl.getLockedAmount(tokenId), 2e18);

        vm.prank(address(vesting));
        vePearl.updateVestingDuration(tokenId, 2 days);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InsufficientVestingDuration.selector, 2 days));
        vePearl.depositFor(tokenId, 1e18);
    }

    function test_merge() public {
        pearl.approve(address(vePearl), 2e18);

        uint256 tokenId1 = vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        uint256 tokenId2 = vePearl.mint(address(this), 1e18, 1 * 52 weeks);

        vm.expectRevert(VotingEscrow.SelfMerge.selector);
        vePearl.merge(tokenId1, tokenId1);

        vePearl.merge(tokenId1, tokenId2);

        assertEq(vePearl.getVotes(address(this)), 2e18);
        assertEq(vePearl.getLockedAmount(tokenId1), 0);
        assertEq(vePearl.getLockedAmount(tokenId2), 2e18);
        assertEq(vePearl.getRemainingVestingDuration(tokenId2), 2 * 52 weeks);
    }

    function test_split() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        uint256[] memory shares = new uint256[](1);
        shares[0] = 100;

        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidSharesLength.selector, 1));
        uint256[] memory tokenIds = vePearl.split(tokenId, shares);

        shares = new uint256[](3);
        shares[0] = 5;
        shares[1] = 3;
        shares[2] = 2;

        tokenIds = vePearl.split(tokenId, shares);

        assertEq(tokenIds.length, 3);
        assertEq(tokenIds[0], tokenId);
        assertEq(tokenIds[1], tokenId + 1);
        assertEq(tokenIds[2], tokenId + 2);

        assertEq(vePearl.getVotes(address(this)), 1e18);
        assertEq(vePearl.getLockedAmount(tokenIds[0]), 0.5e18);
        assertEq(vePearl.getLockedAmount(tokenIds[1]), 0.3e18);
        assertEq(vePearl.getLockedAmount(tokenIds[2]), 0.2e18);
    }

    function test_invalidSplit() public {
        pearl.approve(address(vePearl), 1);

        uint256 tokenId = vePearl.mint(address(this), 1, 2 * 52 weeks);

        uint256[] memory shares = new uint256[](2);
        shares[0] = 7;
        shares[1] = 3;

        vm.expectRevert(VotingEscrow.ZeroLockBalance.selector);
        vePearl.split(tokenId, shares);

        shares = new uint256[](2);
        shares[0] = 0;
        shares[1] = 1;

        vm.expectRevert(VotingEscrow.ZeroLockBalance.selector);
        vePearl.split(tokenId, shares);
    }

    function test_splitApproval() public {
        pearl.approve(address(vePearl), 10);

        uint256 tokenId = vePearl.mint(address(this), 10, 2 * 52 weeks);
        vePearl.approve(bob, tokenId);

        vm.startPrank(bob);
        uint256[] memory shares = new uint256[](2);
        shares[0] = 7;
        shares[1] = 3;

        uint256[] memory tokenIds = vePearl.split(tokenId, shares);
        assertEq(vePearl.getApproved(tokenIds[0]), bob);
        assertEq(vePearl.getApproved(tokenIds[1]), bob);
    }

    function test_updateVestingDuration() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 52 weeks);

        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrow.InvalidVestingDuration.selector, 50 weeks, 52 weeks, 104 weeks)
        );
        vePearl.updateVestingDuration(tokenId, 50 weeks);

        vm.expectRevert(
            abi.encodeWithSelector(VotingEscrow.InvalidVestingDuration.selector, 200 weeks, 52 weeks, 104 weeks)
        );
        vePearl.updateVestingDuration(tokenId, 200 weeks);

        vm.prank(address(vesting));
        vm.expectRevert(abi.encodeWithSelector(VotingEscrow.InvalidVestingDuration.selector, 200 weeks, 0, 104 weeks));
        vePearl.updateVestingDuration(tokenId, 200 weeks);

        vePearl.updateVestingDuration(tokenId, 100 weeks);
        assertEq(vePearl.getRemainingVestingDuration(tokenId), 100 weeks);

        vm.recordLogs();
        vePearl.updateVestingDuration(tokenId, 100 weeks);
        assertEq(vePearl.getRemainingVestingDuration(tokenId), 100 weeks);
        assertEq(vm.getRecordedLogs().length, 0);
    }

    function test_transfer() public {
        pearl.approve(address(vePearl), 2e18);

        uint256 tokenId1 = vePearl.mint(address(this), 1e18, 2 * 52 weeks);
        uint256 tokenId2 = vePearl.mint(address(this), 1e18, 1 * 52 weeks);

        vm.expectCall(address(voter), abi.encodeCall(voter.poke, (address(this))), 2);
        vm.expectCall(address(voter), abi.encodeCall(voter.poke, (alice)), 1);
        vm.expectCall(address(voter), abi.encodeCall(voter.poke, (bob)), 1);

        vePearl.transferFrom(address(this), alice, tokenId1);
        vePearl.transferFrom(address(this), bob, tokenId2);

        assertEq(vePearl.getVotes(address(this)), 0);
        assertEq(vePearl.getVotes(alice), 1e18);
        assertEq(vePearl.getVotes(bob), 0.5e18);
    }

    function test_burn() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        skip(52 weeks);
        vesting.withdraw(address(this), tokenId);

        vm.expectRevert(abi.encodeWithSelector(VotingEscrowVesting.VestingNotFinished.selector));
        vePearl.burn(address(this), tokenId);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        skip(52 weeks);
        vesting.withdraw(address(this), tokenId);

        vePearl.burn(address(this), tokenId);

        assertEq(pearl.balanceOf(address(this)), 100e18);
    }

    function test_pastVotingPower() public {
        pearl.approve(address(vePearl), 2e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 2 * 52 weeks);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        skip(52 weeks);
        vesting.withdraw(address(this), tokenId);

        skip(1 days);
        vePearl.depositFor(tokenId, 1e18);

        vePearl.approve(address(vesting), tokenId);
        vesting.deposit(tokenId);

        skip(52 weeks);

        assertEq(vePearl.getPastVotingPower(tokenId, 52 weeks + 1), 0.5e18);
        assertEq(vePearl.getPastTotalVotingPower(52 weeks + 1), 0.5e18);

        bytes memory errorData =
            abi.encodeWithSelector(VotesUpgradeable.ERC5805FutureLookup.selector, block.timestamp, block.timestamp);

        vm.expectRevert(errorData);
        vePearl.getPastTotalVotingPower(block.timestamp);

        vm.expectRevert(errorData);
        vePearl.getPastVotingPower(tokenId, block.timestamp);
    }

    function test_tokenURI() public {
        pearl.approve(address(vePearl), 1e18);

        uint256 tokenId = vePearl.mint(address(this), 1e18, 52 weeks);

        vm.expectRevert();
        vePearl.tokenURI(0);

        assertNotEq(bytes(vePearl.tokenURI(tokenId)).length, 0);
    }
}
