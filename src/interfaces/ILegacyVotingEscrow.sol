// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

interface ILegacyVotingEscrow {
    function locked(uint256 tokenId) external view returns (int128, uint256);
}
