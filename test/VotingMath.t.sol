// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/governance/VotingMath.sol";

contract VotingMathHelper {
    function calculateVotingPower(uint256 amount, uint256 remainingDuration) external pure returns (uint256) {
        return VotingMath.calculateVotingPower(amount, remainingDuration);
    }
}

contract VotingMathTest is Test {
    VotingMathHelper helper;

    function setUp() public {
        helper = new VotingMathHelper();
    }

    function test_calculateVotingPower() public {
        assertEq(helper.calculateVotingPower(1e18, VotingMath.MAX_VESTING_DURATION), 1e18);
        assertEq(helper.calculateVotingPower(1e18, VotingMath.MAX_VESTING_DURATION / 2), 0.5e18);
    }
}
