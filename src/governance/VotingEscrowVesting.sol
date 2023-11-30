// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC6372} from "@openzeppelin/contracts/interfaces/IERC6372.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @title Voting Escrow Vesting Contract
 * @author SeaZarrgh
 * @notice VotingEscrowVesting manages the vesting of tokens locked in the Voting Escrow system. It enables users to
 * deposit their locked tokens into the contract for vesting, and withdraw or claim them based on the vesting schedule.
 * The contract extends the functionality of the Voting Escrow system by providing a vesting mechanism for locked
 * tokens.
 *
 * @dev The contract uses ReentrancyGuard to prevent reentrancy attacks and implements IERC6372 for standardized clock
 * functionality.
 *
 *      Key features include:
 *      - Depositing locked tokens from the Voting Escrow contract and initiating a vesting schedule.
 *      - Withdrawing tokens after the vesting period, optionally leaving some vesting period remaining.
 *      - Claiming tokens after vesting, effectively burning the Voting Escrow NFT representing the locked tokens.
 *      - Maintaining a record of deposited tokens per user and their vesting schedules.
 *      - Implements `clock` and `CLOCK_MODE` functions as per ERC-6372 for standardized time handling.
 *
 * The contract includes safety checks and custom errors for robust error handling and user feedback.
 */
contract VotingEscrowVesting is ReentrancyGuard, IERC6372 {
    struct VestingSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
    }

    mapping(address owner => uint256[]) private _depositedTokens;
    mapping(uint256 tokenId => uint256) private _depositedTokensIndex;

    mapping(uint256 tokenId => VestingSchedule) vestingSchedules;
    mapping(uint256 tokenId => address owner) depositors;

    IVotingEscrow public immutable votingEscrow;

    error NotAuthorized(address account);
    error VestingNotFinished();
    error OutOfBoundsIndex(address depositor, uint256 index);

    constructor(address votingEscrow_) {
        votingEscrow = IVotingEscrow(votingEscrow_);
    }

    /**
     * @notice Returns the number of tokens deposited by a specific depositor.
     * @dev Provides the count of tokens that have been deposited into the vesting contract by a given address. This
     * function is useful for understanding the extent of participation of a depositor in the vesting process.
     * @param depositor The address of the depositor whose token count is being queried.
     * @return The number of tokens deposited by the specified depositor.
     */
    function balanceOf(address depositor) external view returns (uint256) {
        return _depositedTokens[depositor].length;
    }

    /**
     * @notice Retrieves the vesting schedule for a specific tokenId.
     * @dev Returns the vesting schedule details associated with a particular tokenId. The vesting schedule includes
     * start time, end time, and the amount of tokens being vested. This information is crucial for users to understand
     * the vesting status and timeline of their tokens.
     * @param tokenId The unique identifier of the token whose vesting schedule is being queried.
     * @return A `VestingSchedule` struct containing the start time, end time, and amount of the vesting token.
     */
    function getSchedule(uint256 tokenId) external view returns (VestingSchedule memory) {
        return vestingSchedules[tokenId];
    }

    /**
     * @notice Retrieves the tokenId of a token deposited by a depositor at a specific index.
     * @dev Provides the tokenId of a deposited token based on the depositor's address and the index in their deposit
     * array. This is useful for enumerating over all tokens deposited by a single address.
     * @param depositor The address of the depositor whose tokens are being queried.
     * @param index The index in the depositor's list of tokens.
     * @return The tokenId of the deposited token at the specified index for the given depositor.
     * @custom:error OutOfBoundsIndex Indicates that the index provided is out of bounds for the depositor's token list.
     */
    function tokenOfDepositorByIndex(address depositor, uint256 index) public view virtual returns (uint256) {
        uint256[] storage tokens = _depositedTokens[depositor];
        if (index >= tokens.length) {
            revert OutOfBoundsIndex(depositor, index);
        }
        return tokens[index];
    }

    /**
     * @notice Deposits a token into the vesting contract for a specific duration.
     * @dev Allows a user to deposit a token into the vesting contract. The function calculates the vesting duration,
     * sets up the vesting schedule, and transfers the token to the contract. It also updates the vesting duration in
     * the Voting Escrow contract to remove the voting power during the vesting period. This function uses the
     * nonReentrant modifier to prevent reentrancy attacks.
     * @param tokenId The unique identifier of the token being deposited.
     */
    function deposit(uint256 tokenId) external nonReentrant {
        uint256 duration = votingEscrow.getRemainingVestingDuration(tokenId);
        uint256 startTime = clock();
        uint256 endTime = startTime + duration;
        uint256 amount = votingEscrow.getLockedAmount(tokenId);
        _addTokenToDepositorEnumeration(msg.sender, tokenId);
        vestingSchedules[tokenId] = VestingSchedule(startTime, endTime, amount);
        votingEscrow.updateVestingDuration(tokenId, 0); // effectively remove voting power during vesting
        votingEscrow.transferFrom(msg.sender, address(this), tokenId);
    }

    /**
     * @notice Withdraws a token from the vesting contract, potentially before the vesting period is complete.
     * @dev Allows a depositor to withdraw their token from the vesting contract. The function checks if the vesting
     * period is complete and updates the remaining vesting duration accordingly. It also handles the transfer of the
     * token back to a specified receiver. Uses the nonReentrant modifier for added security against reentrancy attacks.
     * @param receiver The address to receive the withdrawn token.
     * @param tokenId The unique identifier of the token being withdrawn.
     * @custom:error NotAuthorized Indicates the caller is not authorized to withdraw the specified token.
     */
    function withdraw(address receiver, uint256 tokenId) external nonReentrant {
        if (depositors[tokenId] != msg.sender) {
            revert NotAuthorized(msg.sender);
        }

        VestingSchedule storage tokenSchedule = vestingSchedules[tokenId];
        uint256 endTime = tokenSchedule.endTime;

        // If the end time is smaller than or equal to the current time, we intentionally want the remaining time to
        // keep its initial default value of 0.
        // slither-disable-next-line uninitialized-local
        uint256 remainingTime;

        if (endTime > clock()) {
            unchecked {
                remainingTime = endTime - clock();
            }
        }

        _removeTokenFromDepositorEnumeration(msg.sender, tokenId);

        votingEscrow.transferFrom(address(this), receiver, tokenId);
        votingEscrow.updateVestingDuration(tokenId, remainingTime);
    }

    /**
     * @notice Claims a token from the vesting contract after the vesting period is complete, effectively burning the
     * token.
     * @dev Enables a depositor to claim their token, burning the associated Voting Escrow NFT, after the vesting period
     * ends. Verifies that the vesting period has ended before allowing the claim. Removes the token from the
     * depositor's enumeration and burns the token in the Voting Escrow contract. Uses the nonReentrant modifier to
     * safeguard against reentrancy attacks.
     * @param receiver The address to receive any potential benefits from the burned token.
     * @param tokenId The unique identifier of the token being claimed.
     * @custom:error NotAuthorized Indicates the caller is not authorized to claim the specified token.
     * @custom:error VestingNotFinished Indicates the vesting period for the token is not yet complete.
     */
    function claim(address receiver, uint256 tokenId) external nonReentrant {
        if (depositors[tokenId] != msg.sender) {
            revert NotAuthorized(msg.sender);
        }

        VestingSchedule storage tokenSchedule = vestingSchedules[tokenId];

        if (tokenSchedule.endTime > clock()) {
            revert VestingNotFinished();
        }

        _removeTokenFromDepositorEnumeration(msg.sender, tokenId);

        votingEscrow.burn(receiver, tokenId);
    }

    /**
     * @notice Provides the current timestamp as per the contract's internal clock.
     * @dev Implements a standardized clock as defined in ERC-6372, returning the current timestamp as a uint48. This
     * function is used throughout the contract for time-related calculations, ensuring consistent time handling.
     * @return The current timestamp as a uint48, per ERC-6372 standard.
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @notice Describes the clock mode used in the contract as per ERC-6372.
     * @dev Provides a machine-readable description of the clock used, following the ERC-6372 standard. This function
     * specifies the mode of the clock, indicating the type of time measurement used in the contract. It plays a crucial
     * role in ensuring transparent and standardized time handling for contract operations.
     * @return A string representing the clock mode, confirming the use of a timestamp-based clock.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @notice Internal function to add a token to the enumeration of tokens deposited by a specific depositor.
     * @dev Adds a tokenId to the depositor's list of deposited tokens and updates the relevant mappings. This function
     * is called during the deposit process to track each depositor's tokens.
     * @param to The address of the depositor.
     * @param tokenId The unique identifier of the token being deposited.
     */
    function _addTokenToDepositorEnumeration(address to, uint256 tokenId) private {
        uint256[] storage tokens = _depositedTokens[to];
        depositors[tokenId] = to;
        _depositedTokensIndex[tokenId] = tokens.length;
        tokens.push(tokenId);
    }

    /**
     * @notice Internal function to remove a token from the enumeration of tokens deposited by a specific depositor.
     * @dev Removes a tokenId from the depositor's list of deposited tokens and updates the relevant mappings. This
     * function is invoked during the withdrawal or claim process to accurately reflect the current state of deposits.
     * @param from The address of the depositor.
     * @param tokenId The unique identifier of the token being removed.
     */
    function _removeTokenFromDepositorEnumeration(address from, uint256 tokenId) private {
        uint256[] storage tokens = _depositedTokens[from];

        uint256 lastTokenIndex = tokens.length - 1;
        uint256 tokenIndex = _depositedTokensIndex[tokenId];

        assert(tokens[tokenIndex] == tokenId);

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = tokens[lastTokenIndex];
            tokens[tokenIndex] = lastTokenId;
            _depositedTokensIndex[lastTokenId] = tokenIndex;
        }

        delete _depositedTokensIndex[tokenId];
        tokens.pop();

        delete depositors[tokenId];
        delete vestingSchedules[tokenId];
    }
}
