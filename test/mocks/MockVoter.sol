// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "../../src/interfaces/IVoter.sol";

contract MockVoter is IVoter {
    function poke(address voter) external override {}
}
