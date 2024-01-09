// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Checkpoints} from "@openzeppelin/contracts/utils/structs/Checkpoints.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Time} from "@openzeppelin/contracts/utils/types/Time.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {VotesUpgradeable} from "@openzeppelin/contracts-upgradeable/governance/utils/VotesUpgradeable.sol";
import {ERC721EnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";
import {VotingMath} from "./VotingMath.sol";

import {IVoter} from "../interfaces/IVoter.sol";
import {VotingEscrowArtProxy} from "../ui/VotingEscrowArtProxy.sol";

/**
 * @title Voting Escrow Contract
 * @author SeaZarrgh
 * @notice VotingEscrow is a UUPS-upgradeable contract that manages locked tokens for governance purposes. It extends
 * ERC721EnumerableUpgradeable to represent locked tokens as NFTs, allowing for tokenized governance rights. The
 * contract allows users to lock tokens in exchange for voting power, represented by an NFT. The voting power decreases
 * over time as the lock approaches its expiry, encouraging continuous participation.
 *
 * @dev The contract leverages various OpenZeppelin libraries and contracts for upgradeability, ownership, and token
 * handling.
 *
 *      Key features include:
 *      - Token locking mechanism with adjustable vesting duration within set bounds.
 *      - ERC721 token representation of locked tokens, facilitating transfer and management of voting rights.
 *      - Integration with a custom art proxy for dynamic NFT representation.
 *      - Voting power calculation based on locked amount and vesting duration.
 *      - Custom error handling for various failure scenarios.
 *      - Functions for minting, burning, splitting, and merging of voting escrow tokens.
 *
 * The contract employs a unique storage pattern for upgrade safety and uses Checkpoints for efficient voting power
 * tracking. It is designed with modularity, security, and gas efficiency in mind.
 */
contract VotingEscrow is
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    VotesUpgradeable,
    UUPSUpgradeable,
    IVotingEscrow
{
    using SafeERC20 for IERC20;
    using VotingMath for uint256;
    using Checkpoints for Checkpoints.Trace208;

    uint256 public constant MIN_VESTING_DURATION = 2 weeks;
    uint256 public constant MAX_VESTING_DURATION = VotingMath.MAX_VESTING_DURATION;

    IERC20 public immutable lockedToken;

    /// @custom:storage-location erc7201:pearl.storage.VotingEscrow
    struct VotingEscrowStorage {
        address vestingContract;
        VotingEscrowArtProxy artProxy;
        IVoter voter;
        uint256 _tokenId;
        Checkpoints.Trace208 _totalVotingPowerCheckpoints;
        mapping(uint256 tokenId => Checkpoints.Trace208) _votingPowerCheckpoints;
        mapping(uint256 tokenId => uint256) _lockedBalance;
        mapping(uint256 tokenId => uint256) _remainingVestingDuration;
        mapping(address account => uint256) _accountVotingPower;
        mapping(uint256 tokenId => uint48) _mintingTimestamp;
        mapping(address account => bool) _defaultDelegateSet;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.VotingEscrow")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VotingEscrowStorageLocation =
        0x0f3825c50c244aa9bc1c5f3f2ce9fd405afa88de83db180511c2494f49286500;

    function _getVotingEscrowStorage() private pure returns (VotingEscrowStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := VotingEscrowStorageLocation
        }
    }

    error InvalidZeroAddress();
    error InvalidSharesLength(uint256 length);
    error InvalidVestingDuration(uint256 duration, uint256 min, uint256 max);
    error NotAuthorized(address account);
    error VestingNotFinished();
    error ZeroLockBalance();

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address _lockedToken) {
        lockedToken = IERC20(_lockedToken);
        _disableInitializers();
    }

    /**
     * @notice Authorizes a new contract implementation for an upgrade.
     * @dev Overrides the `_authorizeUpgrade` function from the UUPSUpgradeable contract. It restricts the upgrade
     * functionality to the contract owner, enhancing security by preventing unauthorized upgrades. This function is a
     * key part of the UUPS (Universal Upgradeable Proxy Standard) pattern.
     * @param newImplementation The address of the new contract implementation for the upgrade.
     * @custom:security-note Ensure that the `newImplementation` address points to a trusted and thoroughly audited new
     * contract version.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the VotingEscrow contract with necessary parameters.
     * @dev This function sets up the contract with initial parameters for the vesting contract, voter interface, and
     * art proxy. It should be called only once immediately after deployment. The initializer sets up ERC721 token
     * details and initializes the Ownable and UUPSUpgradeable aspects of the contract.
     * @param _vestingContract The address of the vesting contract to be associated with VotingEscrow.
     * @param _voter The address of the voter contract interface.
     * @param _artProxy The address of the art proxy contract for NFT representation.
     */
    function initialize(address _vestingContract, address _voter, address _artProxy) external initializer {
        __ERC721_init("Pearl Voting Escrow", "vePEARL");
        __Ownable_init(_msgSender());
        __Votes_init();
        __UUPSUpgradeable_init();

        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.vestingContract = _vestingContract;
        $.voter = IVoter(_voter);
        $.artProxy = VotingEscrowArtProxy(_artProxy);
    }

    /**
     * @notice Retrieves the address of the art proxy contract.
     * @dev Returns the address of the VotingEscrowArtProxy contract associated with this VotingEscrow contract. The art
     * proxy is responsible for generating the tokenURI for NFTs representing locked tokens. This view function provides
     * an interface to access the art proxy's address.
     * @return The address of the currently set art proxy contract.
     */
    function artProxy() external view returns (address) {
        return address(_getVotingEscrowStorage().artProxy);
    }

    /**
     * @notice Retrieves the address of the vesting contract associated with this VotingEscrow contract.
     * @dev Returns the address of the contract that handles the vesting of tokens. This function provides a way to
     * access the address of the vesting contract used by the VotingEscrow contract. The vesting contract is integral to
     * the token lock and vesting mechanism of the VotingEscrow system.
     * @return The address of the vesting contract.
     */
    function vestingContract() external view returns (address) {
        return _getVotingEscrowStorage().vestingContract;
    }

    /**
     * @notice Retrieves the address of the voter contract interface.
     * @dev Returns the address of the IVoter contract interface. The voter interface is used for integrating voting
     * mechanics within the VotingEscrow system. This function provides an accessible way to query the address of the
     * voter interface.
     * @return The address of the voter contract interface.
     */
    function voter() external view returns (address) {
        return address(_getVotingEscrowStorage().voter);
    }

    /**
     * @notice Retrieves the locked amount for a specific tokenId.
     * @dev Returns the amount of tokens locked in the VotingEscrow contract corresponding to a given tokenId. This
     * function is useful for querying the amount of tokens that are locked and represented by a specific NFT.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @return The amount of tokens locked for the specified tokenId.
     */
    function getLockedAmount(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._lockedBalance[tokenId];
    }

    /**
     * @notice Retrieves the minting timestamp of a specific tokenId.
     * @dev Returns the timestamp at which the NFT, represented by the given tokenId, was minted in the VotingEscrow
     * contract. This function is useful for tracking the age of a specific lock and its associated NFT.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @return The timestamp of when the NFT with the specified tokenId was minted.
     */
    function getMintingTimestamp(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._mintingTimestamp[tokenId];
    }

    /**
     * @notice Retrieves the total voting power at a past timepoint.
     * @dev Uses the checkpointing system to provide historical voting power data. This function is important for
     * governance and voting mechanisms, allowing to query past total voting power. Reverts if the queried timepoint is
     * in the future.
     * @param timepoint The historical timestamp for which the total voting power is being queried.
     * @return The total voting power at the specified historical timepoint.
     * @custom:error ERC5805FutureLookup Indicates an attempt to query a future timepoint.
     */
    function getPastTotalVotingPower(uint256 timepoint) external view returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return $._totalVotingPowerCheckpoints.upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    /**
     * @notice Retrieves the voting power of a specific tokenId at a past timepoint.
     * @dev Uses the checkpointing system to provide historical voting power data for a specific tokenId. This function
     * is crucial for governance, allowing queries of past voting power of individual token locks. Reverts if the
     * queried timepoint is in the future, ensuring only historical data is accessed.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @param timepoint The historical timestamp for which the voting power is being queried.
     * @return The voting power associated with the specified tokenId at the historical timepoint.
     * @custom:error ERC5805FutureLookup Indicates an attempt to query a future timepoint.
     */
    function getPastVotingPower(uint256 tokenId, uint256 timepoint) external view returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint48 currentTimepoint = clock();
        if (timepoint >= currentTimepoint) {
            revert ERC5805FutureLookup(timepoint, currentTimepoint);
        }
        return $._votingPowerCheckpoints[tokenId].upperLookupRecent(SafeCast.toUint48(timepoint));
    }

    /**
     * @notice Retrieves the remaining vesting duration for a specific tokenId.
     * @dev Returns the amount of time (in seconds) left until the vesting is complete for the locked tokens represented
     * by the given tokenId. This function is useful for understanding the time left before the locked tokens can be
     * fully accessed or before the voting power depletes.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @return The remaining vesting duration (in seconds) for the specified tokenId.
     */
    function getRemainingVestingDuration(uint256 tokenId) external view returns (uint256) {
        return _getVotingEscrowStorage()._remainingVestingDuration[tokenId];
    }

    /**
     * @notice Provides the URI for the token metadata of a specific tokenId.
     * @dev Returns a URL pointing to the metadata of the NFT represented by the given tokenId. The metadata includes
     * details about the locked tokens and vesting duration. The function uses the VotingEscrowArtProxy to generate the
     * tokenURI dynamically. It requires that the tokenId must be owned (not burned) to return a valid URI.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @return A string URL to the token metadata.
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        return $.artProxy.tokenURI(tokenId, $._lockedBalance[tokenId], $._remainingVestingDuration[tokenId]);
    }

    /**
     * @notice Sets or updates the address of the art proxy contract.
     * @dev Allows the contract owner to change the address of the VotingEscrowArtProxy contract. The art proxy is
     * responsible for generating dynamic NFT metadata based on locked tokens and vesting duration. Reverts if the new
     * art proxy address is the zero address to prevent invalid configuration.
     * @param _artProxy The new address of the art proxy contract.
     * @custom:error InvalidZeroAddress Indicates an attempt to set the art proxy to the zero address.
     */
    function setArtProxy(address _artProxy) external onlyOwner {
        if (_artProxy == address(0)) {
            revert InvalidZeroAddress();
        }
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.artProxy = VotingEscrowArtProxy(_artProxy);
    }

    /**
     * @notice Sets or updates the address of the voter contract.
     * @dev Allows the contract owner to change the address of the voter contract interface (IVoter). The voter contract
     * is used for integrating voting mechanisms within the VotingEscrow system. Reverts if the new voter address is the
     * zero address, ensuring a valid configuration.
     * @param _voter The new address of the voter contract interface.
     * @custom:error InvalidZeroAddress Indicates an attempt to set the voter to the zero address.
     */
    function setVoter(address _voter) external onlyOwner {
        if (_voter == address(0)) {
            revert InvalidZeroAddress();
        }
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.voter = IVoter(_voter);
    }

    /**
     * @notice Mints a new voting escrow NFT to a receiver with a specified locked balance and vesting duration.
     * @dev Creates a new token representing locked tokens in the VotingEscrow contract. The amount of locked tokens and
     * vesting duration determine the voting power of the NFT. Reverts if locked balance is zero or if the vesting
     * duration is outside the allowed range. Transfers the locked tokens from the sender to the contract.
     * @param receiver The address to receive the newly minted NFT.
     * @param lockedBalance The amount of tokens to be locked.
     * @param vestingDuration The duration for which the tokens will be locked.
     * @return tokenId The unique identifier of the newly minted NFT.
     * @custom:error ZeroLockBalance Indicates that the locked balance is zero.
     * @custom:error InvalidVestingDuration Indicates that the vesting duration is outside the allowed range.
     */
    function mint(address receiver, uint256 lockedBalance, uint256 vestingDuration)
        external
        returns (uint256 tokenId)
    {
        if (lockedBalance == 0) {
            revert ZeroLockBalance();
        }
        if (vestingDuration < MIN_VESTING_DURATION || vestingDuration > MAX_VESTING_DURATION) {
            revert InvalidVestingDuration(vestingDuration, MIN_VESTING_DURATION, MAX_VESTING_DURATION);
        }
        tokenId = _incrementAndGetTokenId();
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $._mintingTimestamp[tokenId] = clock();
        _mint(receiver, tokenId);
        _updateLock(tokenId, lockedBalance, vestingDuration);
        lockedToken.safeTransferFrom(_msgSender(), address(this), lockedBalance);
    }

    /**
     * @notice Burns a voting escrow NFT and unlocks the associated tokens.
     * @dev Destroys a token and releases the locked tokens to a specified receiver. Reverts if the vesting period of
     * the token is not yet finished. Transfers the previously locked tokens to the receiver upon successful burning of
     * the token.
     * @param receiver The address that will receive the unlocked tokens.
     * @param tokenId The unique identifier of the NFT to be burned.
     * @custom:error VestingNotFinished Indicates that the vesting duration for the token is still ongoing.
     */
    function burn(address receiver, uint256 tokenId) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        if ($._remainingVestingDuration[tokenId] != 0) {
            revert VestingNotFinished();
        }
        uint256 _lockedBalance = $._lockedBalance[tokenId];
        _updateLock(tokenId, 0, 0);
        _burn(tokenId);
        lockedToken.safeTransfer(receiver, _lockedBalance);
    }

    /**
     * @notice Deposits additional tokens to extend the lock for a specific tokenId.
     * @dev Allows additional tokens to be locked, increasing the voting power of the specified tokenId. The function
     * updates the locked balance and maintains the same vesting duration. This is useful for increasing the locked
     * amount without altering the vesting period. Transfers the additional tokens from the sender to the contract.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @param amount The amount of additional tokens to be locked.
     */
    function depositFor(uint256 tokenId, uint256 amount) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        _updateLock(tokenId, $._lockedBalance[tokenId] + amount, $._remainingVestingDuration[tokenId]);
        lockedToken.safeTransferFrom(_msgSender(), address(this), amount);
    }

    /**
     * @notice Merges two voting escrow NFTs into one, combining their locked balances and extending the vesting
     * duration.
     * @dev Consolidates the locked balances and the longer of the two vesting durations into a single tokenId. The
     * function burns the source tokenId after transferring its balance and vesting duration to the target tokenId.
     * Useful for managing multiple locks by combining them into a single lock with increased voting power.
     * @param tokenId The tokenId of the source NFT to be merged.
     * @param intoTokenId The tokenId of the target NFT into which the source NFT will be merged.
     */
    function merge(uint256 tokenId, uint256 intoTokenId) external {
        address owner = _requireOwned(tokenId);
        address targetOwner = _requireOwned(intoTokenId);

        _checkAuthorized(owner, _msgSender(), tokenId);
        _checkAuthorized(targetOwner, _msgSender(), intoTokenId);

        VotingEscrowStorage storage $ = _getVotingEscrowStorage();

        uint256 _lockedBalance = $._lockedBalance[tokenId] + $._lockedBalance[intoTokenId];
        uint256 remainingVestingDuration =
            Math.max($._remainingVestingDuration[tokenId], $._remainingVestingDuration[intoTokenId]);

        _updateLock(tokenId, 0, 0);
        _updateLock(intoTokenId, _lockedBalance, remainingVestingDuration);

        _burn(tokenId);
    }

    /**
     * @notice Splits a voting escrow NFT into multiple NFTs based on specified shares.
     * @dev Divides the locked balance of an NFT into several new NFTs, each with a portion of the original locked
     * balance and vesting duration. This function is useful for distributing voting power among multiple parties or
     * addresses. Reverts if the number of shares is less than two, as splitting into less than two parts is not
     * meaningful.
     * @param tokenId The tokenId of the NFT to be split.
     * @param shares An array representing the proportion of the locked balance to be allocated to each new NFT.
     * @return tokenIds An array of new tokenIds created as a result of the split.
     * @custom:error InvalidSharesLength Indicates that the number of shares specified is invalid (less than two).
     */
    function split(uint256 tokenId, uint256[] calldata shares) external returns (uint256[] memory tokenIds) {
        if (shares.length < 2) {
            revert InvalidSharesLength(shares.length);
        }
        address owner = _requireOwned(tokenId);
        _checkAuthorized(owner, _msgSender(), tokenId);
        tokenIds = new uint[](shares.length);
        tokenIds[0] = tokenId;
        uint256 totalShares;
        for (uint256 i = shares.length; i != 0;) {
            unchecked {
                --i;
            }
            totalShares += shares[i];
        }
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint256 remainingVestingDuration = $._remainingVestingDuration[tokenId];
        uint256 lockedBalance = $._lockedBalance[tokenId];
        uint256 remainingBalance = lockedBalance;
        uint48 mintingTimestamp = clock();
        for (uint256 i = 1; i < shares.length;) {
            uint256 share = shares[i];
            uint256 _lockedBalance = share * lockedBalance / totalShares;
            uint256 newTokenId = _incrementAndGetTokenId();
            tokenIds[i] = newTokenId;
            $._mintingTimestamp[newTokenId] = mintingTimestamp;
            _mint(owner, newTokenId);
            _updateLock(newTokenId, _lockedBalance, remainingVestingDuration);
            unchecked {
                remainingBalance -= _lockedBalance;
                ++i;
            }
        }
        _updateLock(tokenId, remainingBalance, remainingVestingDuration);
    }

    /**
     * @notice Updates the vesting duration for a specific tokenId.
     * @dev Allows changing the vesting duration of the locked tokens represented by a tokenId. If called by the vesting
     * contract, there's no restriction on reducing the vesting duration. Otherwise, the caller must be authorized, and
     * the new duration cannot be shorter than the current one. Reverts if the new duration is the same as the current
     * duration or if it exceeds the maximum allowed duration.
     * @param tokenId The unique identifier of the NFT representing the locked tokens.
     * @param vestingDuration The new vesting duration in seconds.
     * @custom:error InvalidVestingDuration Indicates an invalid vesting duration, either too short, too long, or
     * unchanged.
     */
    function updateVestingDuration(uint256 tokenId, uint256 vestingDuration) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        uint256 remainingVestingDuration = $._remainingVestingDuration[tokenId];
        if (vestingDuration == remainingVestingDuration) return;
        if ($.vestingContract != _msgSender()) {
            _checkAuthorized(ownerOf(tokenId), _msgSender(), tokenId);
            if (vestingDuration < remainingVestingDuration || vestingDuration > MAX_VESTING_DURATION) {
                revert InvalidVestingDuration(vestingDuration, remainingVestingDuration, MAX_VESTING_DURATION);
            }
        }
        if (vestingDuration > MAX_VESTING_DURATION) {
            revert InvalidVestingDuration(vestingDuration, 0, MAX_VESTING_DURATION);
        }
        _updateLock(tokenId, $._lockedBalance[tokenId], vestingDuration);
    }

    /**
     * @notice Provides the current timestamp, complying with ERC-6372 for time-based token systems.
     * @dev Implements the ERC-6372 standard's clock functionality, returning the current timestamp as a uint48. This
     * standard is crucial for time-dependent token systems, providing a unified approach to time tracking.
     * @return The current timestamp as per ERC-6372 specifications.
     */
    function clock() public view virtual override returns (uint48) {
        return Time.timestamp();
    }

    /**
     * @notice Describes the clock mode used in the contract as per ERC-6372.
     * @dev Provides a machine-readable description of the clock used, following the ERC-6372 standard. This function
     * specifies the mode of the clock, indicating the type of time measurement used in the contract. It is an important
     * part of the ERC-6372 standard, offering transparency and consistency in time handling.
     * @return A string representing the clock mode, confirming the use of a timestamp-based clock.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure virtual override returns (string memory) {
        return "mode=timestamp";
    }

    /**
     * @notice Internal function to update the lock parameters for a specified token.
     * @dev Adjusts the locked balance and vesting duration of a token and recalculates its voting power. This function
     * is a key component in managing the state of locked tokens. It ensures that the voting power is accurately
     * adjusted based on the new lock parameters. Invoked during token minting, burning, deposit, and vesting duration
     * updates.
     * @param tokenId The identifier of the token being updated.
     * @param lockedBalance The new locked balance for the token.
     * @param vestingDuration The new vesting duration for the token.
     */
    function _updateLock(uint256 tokenId, uint256 lockedBalance, uint256 vestingDuration) internal {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        address owner = _requireOwned(tokenId);
        uint48 timepoint = SafeCast.toUint48(clock());
        uint208 votingPowerBefore = $._votingPowerCheckpoints[tokenId].latest();
        uint208 votingPower = SafeCast.toUint208(lockedBalance.calculateVotingPower(vestingDuration));
        uint256 lockedBalanceBefore = $._lockedBalance[tokenId];

        if (lockedBalance != lockedBalanceBefore) {
            $._lockedBalance[tokenId] = lockedBalance;
        }

        if (votingPower != votingPowerBefore) {
            // slither-disable-next-line unused-return
            $._votingPowerCheckpoints[tokenId].push(timepoint, votingPower);
            uint208 totalVotingPower = $._totalVotingPowerCheckpoints.latest();
            // slither-disable-next-line unused-return
            $._totalVotingPowerCheckpoints.push(timepoint, totalVotingPower - votingPowerBefore + votingPower);
        }

        $._remainingVestingDuration[tokenId] = vestingDuration;

        if (votingPowerBefore < votingPower) {
            unchecked {
                _transferVotingUnits(address(0), owner, votingPower - votingPowerBefore);
            }
        } else if (votingPowerBefore > votingPower) {
            unchecked {
                _transferVotingUnits(owner, address(0), votingPowerBefore - votingPower);
            }
        }
    }

    /**
     * @notice Internal function to transfer voting units during token operations.
     * @dev Transfers voting units from one account to another. Invoked during operations that affect voting power, such
     * as token transfers, minting, and burning. Adjusts the voting power of the involved accounts and triggers the
     * voter contract to update their status. No action is taken if the transfer amount is zero.
     * @param from The address from which the voting units are transferred.
     * @param to The address to which the voting units are transferred.
     * @param amount The amount of voting units to transfer.
     */
    function _transferVotingUnits(address from, address to, uint256 amount) internal virtual override {
        if (amount == 0) return;
        super._transferVotingUnits(from, to, amount);
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        if (from != address(0)) {
            $._accountVotingPower[from] -= amount;
            $.voter.poke(from);
        }
        if (to != address(0)) {
            $._accountVotingPower[to] += amount;
            $.voter.poke(to);
        }
    }

    /**
     * @notice Internal function to update internal state during token transfers.
     * @dev Ensures proper transfer of voting units and updates delegate settings during token transfers. This function
     * is invoked to manage the transfer of voting rights associated with a token. It adjusts the voting power of the
     * new and previous token owners and sets default delegation.
     * @param to The address receiving the token.
     * @param tokenId The token's identifier being transferred.
     * @param auth The address authorized to perform the update, typically the current token owner.
     * @return The address of the previous owner of the token.
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        address previousOwner = super._update(to, tokenId, auth);

        _setDefaultDelegate(to);
        _transferVotingUnits(previousOwner, to, $._votingPowerCheckpoints[tokenId].latest());

        return previousOwner;
    }

    /**
     * @notice Internal function to handle the delegation logic invoked by the `delegate` function.
     * @dev Overrides the internal delegation logic from the base VotesUpgradeable contract. This function is called
     * internally when a user delegates their voting power using the `delegate` function. It includes the additional
     * logic of setting a default self-delegate for new accounts. This ensures that new accounts have their voting power
     * self-delegated by default, promoting autonomous governance participation.
     * @param account The address of the account delegating its voting power.
     * @param delegatee The address to which the voting power is being delegated.
     */
    function _delegate(address account, address delegatee) internal virtual override {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        if (!$._defaultDelegateSet[account]) {
            $._defaultDelegateSet[account] = true;
        }
        super._delegate(account, delegatee);
    }

    /**
     * @notice Internal function to set the default delegate for an account.
     * @dev Sets an account's default delegate to itself if not already set. This function is called during token
     * transfers and other operations to ensure that each account has a default delegate. The default delegate is used
     * for voting power calculations in governance. No action is taken if the default delegate is already set or if the
     * message sender is the zero address.
     * @param account The address of the account for which the default delegate is being set.
     */
    function _setDefaultDelegate(address account) internal virtual {
        if (_msgSender() == address(0)) return;
        if (_getVotingEscrowStorage()._defaultDelegateSet[account]) return;
        _delegate(account, account);
    }

    /**
     * @notice Internal function to get the voting units (voting power) associated with an account.
     * @dev Returns the total voting power held by an account, as per the current state of the VotingEscrow contract.
     * Voting power is determined by the locked tokens and their vesting duration. This function is used in governance
     * and voting calculations.
     * @param account The address of the account whose voting power is being queried.
     * @return The total voting power (voting units) held by the specified account.
     */
    function _getVotingUnits(address account) internal view virtual override returns (uint256) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        return $._accountVotingPower[account];
    }

    /**
     * @notice Internal function to increment and retrieve the next tokenId.
     * @dev Increments the internal tokenId counter and returns the new tokenId. This function is used to generate
     * unique identifiers for new tokens being minted.
     * @return tokenId The next available unique identifier for a new token.
     */
    function _incrementAndGetTokenId() internal returns (uint256 tokenId) {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $._tokenId = (tokenId = $._tokenId + 1);
    }

    // TODO: remove function below
    function setVestingContract(address _vestingContract) external {
        VotingEscrowStorage storage $ = _getVotingEscrowStorage();
        $.vestingContract = _vestingContract;
    }
}
