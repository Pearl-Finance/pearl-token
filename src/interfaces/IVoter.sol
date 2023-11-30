// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

interface IVoter {
    /**
     * @notice Updates the voting power of a voter.
     * @dev This function is called to resubmit or refresh the most recent vote cast by a given voter, typically used
     * when the voting power of the voter changes. It ensures that the voting power reflects any recent changes, such as
     * token balance adjustments in a token-based voting system.
     * @param voter The address of the voter whose voting power needs to be updated.
     */
    function poke(address voter) external;
}
