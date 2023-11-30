// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IVotingEscrow is IERC721 {
    /**
     * @notice Retrieves the maximum vesting duration for locked tokens.
     * @dev Returns the maximum duration for which tokens can be locked in the escrow for vesting. This duration is a
     * constant value set for the voting escrow system.
     * @return The maximum vesting duration in seconds.
     */
    function MAX_VESTING_DURATION() external view returns (uint256);

    /**
     * @notice Retrieves the token contract used for locking in the voting escrow.
     * @dev Returns the address of the ERC20 token contract used in the voting escrow system for locking tokens.
     * @return An `IERC20` interface representing the locked token contract.
     */
    function lockedToken() external view returns (IERC20);

    /**
     * @notice Retrieves the amount of tokens locked in a specific escrowed token (NFT).
     * @dev Returns the amount of ERC20 tokens locked against a given tokenId (ERC721 token).
     * @param tokenId The ERC721 token ID representing the locked token position.
     * @return The amount of locked tokens corresponding to the given tokenId.
     */
    function getLockedAmount(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Retrieves the timestamp when a specific escrowed token (NFT) was minted.
     * @dev Returns the minting timestamp of a given tokenId (ERC721 token) representing a locked token position.
     * @param tokenId The ERC721 token ID for which the minting timestamp is queried.
     * @return The timestamp of when the tokenId was minted.
     */
    function getMintingTimestamp(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Retrieves the total voting power at a specific past timepoint.
     * @dev Returns the aggregated voting power of all participants in the voting escrow system at a given past
     * timestamp. This function is used to determine the historical voting power at a specific time.
     * @param timepoint The historical timestamp for which the total voting power is queried.
     * @return The total voting power at the specified timepoint.
     */
    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256);

    /**
     * @notice Retrieves the voting power of a specific escrowed token (NFT) at a past timepoint.
     * @dev Returns the voting power associated with a given tokenId (ERC721 token) at a specified past timestamp. This
     * function is useful for historical voting power queries for a specific locked position.
     * @param tokenId The ERC721 token ID representing the locked token position.
     * @param timepoint The historical timestamp for which the voting power is queried.
     * @return The voting power of the specified tokenId at the given timepoint.
     */
    function getPastVotingPower(uint256 tokenId, uint256 timepoint) external view returns (uint256);

    /**
     * @notice Retrieves the remaining vesting duration for a specific escrowed token (NFT).
     * @dev Returns the time left until the vesting period ends for a given tokenId (ERC721 token). This function helps
     * to determine how long the tokens are still locked in the escrow.
     * @param tokenId The ERC721 token ID representing the locked token position.
     * @return The remaining vesting duration in seconds for the given tokenId.
     */
    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256);

    /**
     * @notice Mints a new escrowed token (NFT) with a specified amount of tokens locked for a set vesting duration.
     * @dev Mints an ERC721 token representing a locked token position in the voting escrow. The minted token
     * corresponds to a certain amount of ERC20 tokens locked for a specific vesting duration.
     * @param receiver The address to receive the minted ERC721 token.
     * @param lockedBalance The amount of ERC20 tokens to be locked.
     * @param vestingDuration The duration for which the tokens are to be locked.
     * @return The newly minted tokenId.
     */
    function mint(address receiver, uint256 lockedBalance, uint256 vestingDuration) external returns (uint256);

    /**
     * @notice Burns an escrowed token (NFT), effectively releasing the locked tokens.
     * @dev Destroys a given tokenId (ERC721 token), which represents a locked token position in the voting escrow. This
     * function is called when the locked tokens are to be released or when a vesting position is closed.
     * @param receiver The address that will receive the unlocked ERC20 tokens.
     * @param tokenId The ERC721 token ID representing the locked token position to be burned.
     */
    function burn(address receiver, uint256 tokenId) external;

    /**
     * @notice Deposits additional tokens into an existing escrowed token (NFT) to increase its locked balance.
     * @dev Adds more ERC20 tokens to a locked position represented by a given tokenId (ERC721 token). This function
     * allows users to increase their locked balance, potentially increasing their voting power.
     * @param tokenId The ERC721 token ID representing the locked token position to which the additional tokens are
     * deposited.
     * @param amount The amount of ERC20 tokens to be added to the locked balance.
     */
    function depositFor(uint256 tokenId, uint256 amount) external;

    /**
     * @notice Merges two escrowed tokens (NFTs) into one, combining their locked balances and vesting durations.
     * @dev Combines the locked balances of two tokens represented by their tokenIds (ERC721 tokens) into a single
     * position. This can be used to consolidate voting power or manage multiple locked positions more efficiently.
     * @param tokenId The ERC721 token ID representing the locked token position to be merged.
     * @param intoTokenId The ERC721 token ID into which the first token is to be merged.
     */
    function merge(uint256 tokenId, uint256 intoTokenId) external;

    /**
     * @notice Splits an escrowed token (NFT) into multiple tokens with specified shares of the original locked balance.
     * @dev Divides a locked position represented by a tokenId (ERC721 token) into smaller positions with specific
     * locked balances. This function allows for dividing voting power or managing vesting schedules in a more granular
     * way.
     * @param tokenId The ERC721 token ID representing the locked token position to be split.
     * @param shares An array specifying the proportions of the locked balance to be split into new tokens.
     * @return An array of new tokenIds representing the split positions.
     */
    function split(uint256 tokenId, uint256[] calldata shares) external returns (uint256[] memory);

    /**
     * @notice Updates the vesting duration for a specific escrowed token (NFT).
     * @dev Changes the vesting period of a locked position represented by a tokenId (ERC721 token). This allows
     * adjusting the vesting schedule of locked tokens, potentially affecting the associated voting power.
     * @param tokenId The ERC721 token ID representing the locked token position.
     * @param newDuration The new vesting duration in seconds for the locked position.
     */
    function updateVestingDuration(uint256 tokenId, uint256 newDuration) external;
}
