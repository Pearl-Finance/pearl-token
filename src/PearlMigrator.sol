// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {NonblockingLzAppUpgradeable} from "@tangible/layerzero/lzApp/NonblockingLzAppUpgradeable.sol";

import {IVotingEscrow} from "./interfaces/IVotingEscrow.sol";

/**
 * @title Pearl Migrator
 * @author SeaZarrgh
 * @notice PearlMigrator is responsible for migrating tokens from a legacy Pearl contract to a new Pearl contract
 * across LayerZero. It facilitates the transition of token holdings in a cross-chain environment.
 *
 * @dev The contract extends NonblockingLzAppUpgradeable and UUPSUpgradeable, incorporating functionalities for
 * token migration and contract upgradeability. Key features include burning tokens from the legacy contract, sending
 * cross-chain messages to credit tokens in the new contract, and fee estimation for migrations.
 *
 * Functions:
 * - Migrate tokens by burning them in the legacy contract and initiating a cross-chain message to the new contract.
 * - Estimate fees for token migration across chains.
 * - Handle upgrade authorization as part of the UUPS upgradeability pattern.
 *
 * The contract uses LayerZero for cross-chain communication, ensuring reliable and secure migration of token holdings.
 */
contract PearlMigrator is NonblockingLzAppUpgradeable, UUPSUpgradeable {
    uint256 private constant NO_EXTRA_GAS = 0;

    // packet type
    uint16 private constant PT_SEND = 0;
    uint16 private constant PT_SEND_VE = 1;

    address public immutable legacyPearl;
    address public immutable legacyVEPearl;

    uint16 lzMainChainId;

    event Migrate(address from, address to, uint256 amount);
    event MigrateVE(address from, address to, uint256 tokenId);

    error NonPositiveLockedAmount(int128 amount);
    error LockExpired(uint256 expiry);

    /// @custom:storage-location erc7201:pearl.storage.PearlMigrator
    struct PearlMigratorStorage {
        bool useCustomAdapterParams;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.PearlMigrator")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PearlMigratorStorageLocation =
        0x086e538ddcff28e0d5390fa3e087508bf336263c3dc631586de25a045ce3af00;

    function _getPearlMigratorStorage() private pure returns (PearlMigratorStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := PearlMigratorStorageLocation
        }
    }

    /**
     * @dev Constructor for the PearlMigrator contract. Initializes the contract with LayerZero endpoint, legacy Pearl,
     * main chain ID, and new Pearl contract addresses.
     *
     * It sets up the migration pathway between the legacy Pearl contract and the new Pearl contract, specifying the
     * main chain ID for cross-chain communication.
     *
     * @param lzEndpoint The address of the LayerZero endpoint contract for cross-chain messaging.
     * @param _legacyPearl The address of the legacy Pearl contract from which tokens will be migrated.
     * @param _legacyVEPearl The address of the legacy VE Pearl contract from which tokens will be migrated.
     * @param _lzMainChainId The main chain ID in the LayerZero network, representing the primary network for the Pearl
     * token.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(address lzEndpoint, address _legacyPearl, address _legacyVEPearl, uint16 _lzMainChainId)
        NonblockingLzAppUpgradeable(lzEndpoint)
    {
        legacyPearl = _legacyPearl;
        legacyVEPearl = _legacyVEPearl;
        lzMainChainId = _lzMainChainId;
    }

    /**
     * @dev Authorizes an upgrade to a new implementation of the PearlMigrator contract. This internal function is part
     * of the UUPS upgradeability pattern and is overridden to include access control.
     *
     * The upgrade authorization is restricted to the owner of the contract, ensuring that only a privileged entity can
     * perform upgrades.
     *
     * @param newImplementation The address of the new contract implementation to which the upgrade will occur.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Initializes the PearlMigrator contract. This function sets up initial state variables and configurations for
     * the contract as part of the UUPS upgradeable pattern.
     *
     * This function can only be called once, as it is an initializer.
     */
    function initialize() external initializer {
        __NonblockingLzApp_init(msg.sender);
        PearlMigratorStorage storage $ = _getPearlMigratorStorage();
        $.useCustomAdapterParams = true;
    }

    /**
     * @dev Facilitates the migration of tokens from the legacy Pearl contract to the new Pearl contract. Tokens are
     * burned from the sender's address in the legacy contract and a cross-chain message is sent to credit the tokens
     * in the new contract.
     *
     * @param to The address on the destination chain to receive the migrated tokens.
     * @param refundAddress Address to refund overpaid fees, if any.
     * @param zroPaymentAddress Address for zero token payment, if used.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return amount The amount of tokens that were migrated.
     */
    function migrate(address to, address payable refundAddress, address zroPaymentAddress, bytes calldata adapterParams)
        external
        returns (uint256 amount)
    {
        amount = IERC20(legacyPearl).balanceOf(msg.sender);
        ERC20Burnable(legacyPearl).burnFrom(msg.sender, amount);
        _migrate(amount, msg.sender, to, refundAddress, zroPaymentAddress, adapterParams);
    }

    /**
     * @dev Facilitates the migration of tokens from the legacy vePearl contract to the new vePearl contract. Tokens are
     * burned from the sender's address in the legacy contract and a cross-chain message is sent to credit the tokens
     * in the new contract.
     *
     * @param tokenId The id of the VE token to be migrated.
     * @param to The address on the destination chain to receive the migrated VE token.
     * @param refundAddress Address to refund overpaid fees, if any.
     * @param zroPaymentAddress Address for zero token payment, if used.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     */
    function migrateVotingEscrow(
        uint256 tokenId,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes calldata adapterParams
    ) external {
        IERC721(legacyVEPearl).transferFrom(msg.sender, address(this), tokenId);
        _migrateVotingEscrow(tokenId, msg.sender, to, refundAddress, zroPaymentAddress, adapterParams);
    }

    /**
     * @dev Estimates the fees required for migrating tokens to another chain using LayerZero. This function is useful
     * for users to understand the cost of migration before initiating the transaction.
     *
     * @param dstChainId The destination chain ID for the migration.
     * @param toAddress The address on the destination chain to receive the tokens.
     * @param amount The amount of tokens to migrate.
     * @param useZro Indicates whether to use ZRO token for paying fees.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return nativeFee Estimated native token fee for migration.
     * @return zroFee Estimated ZRO token fee for migration, if ZRO is used.
     */
    function estimateMigrateFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 amount,
        bool useZro,
        bytes calldata adapterParams
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for migrate()
        bytes memory payload = abi.encode(PT_SEND, toAddress, amount);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Estimates the fees required for migrating VE tokens to another chain using LayerZero. This function is
     * useful for users to understand the cost of migration before initiating the transaction.
     *
     * @param dstChainId The destination chain ID for the migration.
     * @param toAddress The address on the destination chain to receive the tokens.
     * @param lockedAmount The locked amount of the VE token to migrate.
     * @param vestingDuration The vesting duration of the VE token to migrate.
     * @param useZro Indicates whether to use ZRO token for paying fees.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     * @return nativeFee Estimated native token fee for migration.
     * @return zroFee Estimated ZRO token fee for migration, if ZRO is used.
     */
    function estimateMigrateVotingEscrowFee(
        uint16 dstChainId,
        bytes calldata toAddress,
        uint256 lockedAmount,
        uint256 vestingDuration,
        bool useZro,
        bytes calldata adapterParams
    ) public view returns (uint256 nativeFee, uint256 zroFee) {
        // mock the payload for migrateVotingEscrow()
        bytes memory payload = abi.encode(PT_SEND_VE, toAddress, lockedAmount, vestingDuration);
        return lzEndpoint.estimateFees(dstChainId, address(this), payload, useZro, adapterParams);
    }

    /**
     * @dev Internal function to handle incoming cross-chain messages. This contract is not designed to receive
     * messages, so any incoming message causes the contract to revert.
     *
     * This function ensures the contract only sends messages and does not process incoming ones, maintaining its
     * intended role as a migrator.
     */
    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory) internal virtual override {
        // Contract should never receive a cross-chain message
        assert(false);
    }

    /**
     * @dev Internal function to handle the migration of tokens. It sends a cross-chain message to the main chain to
     * credit the migrated tokens to the specified address.
     *
     * The function constructs and sends a LayerZero message containing the migration details. It also emits a Migrate
     * event to record the migration action.
     *
     * @param amount The amount of tokens to be migrated.
     * @param from The address of the sender on the source chain.
     * @param to The address on the destination chain to receive the migrated tokens.
     * @param refundAddress Address to refund overpaid fees, if any.
     * @param zroPaymentAddress Address for zero token payment, if used.
     * @param adapterParams Custom adapter parameters for LayerZero message.
     */
    function _migrate(
        uint256 amount,
        address from,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal {
        _checkAdapterParams(lzMainChainId, PT_SEND, adapterParams, NO_EXTRA_GAS);
        bytes memory toAddress = abi.encodePacked(to);
        bytes memory lzPayload = abi.encode(PT_SEND, toAddress, amount);
        _lzSend(lzMainChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);

        emit Migrate(from, to, amount);
    }

    function _migrateVotingEscrow(
        uint256 tokenId,
        address from,
        address to,
        address payable refundAddress,
        address zroPaymentAddress,
        bytes memory adapterParams
    ) internal {
        _checkAdapterParams(lzMainChainId, PT_SEND_VE, adapterParams, NO_EXTRA_GAS);
        bytes memory lockData =
            Address.functionStaticCall(legacyVEPearl, abi.encodeWithSignature("locked(uint256)", tokenId));
        (int128 amount, uint256 end) = abi.decode(lockData, (int128, uint256));
        if (amount <= 0) revert NonPositiveLockedAmount(amount);
        if (end <= block.timestamp) revert LockExpired(end);
        uint256 lockedAmount = uint256(int256(amount));
        uint256 vestingDuration = end - block.timestamp;
        bytes memory toAddress = abi.encodePacked(to);
        bytes memory lzPayload = abi.encode(PT_SEND_VE, toAddress, lockedAmount, vestingDuration);
        _lzSend(lzMainChainId, lzPayload, refundAddress, zroPaymentAddress, adapterParams, msg.value);

        emit MigrateVE(from, to, tokenId);
    }

    /**
     * @dev Internal function to check the adapter parameters for a LayerZero message. It ensures that the parameters
     * are valid and conform to the expected format, based on the contract's settings.
     *
     * This function is crucial for maintaining the integrity and security of the cross-chain migration process. It
     * validates the gas limit and other parameters to prevent misuse or incorrect message formatting.
     *
     * @param dstChainId The destination chain ID for the message.
     * @param pkType The packet type of the message.
     * @param adapterParams The adapter parameters to be validated.
     * @param extraGas Additional gas to be included in the message.
     */
    function _checkAdapterParams(uint16 dstChainId, uint16 pkType, bytes memory adapterParams, uint256 extraGas)
        internal
        virtual
    {
        PearlMigratorStorage storage $ = _getPearlMigratorStorage();
        if ($.useCustomAdapterParams) {
            _checkGasLimit(dstChainId, pkType, adapterParams, extraGas);
        } else {
            require(adapterParams.length == 0, "PearlMigrator: _adapterParams must be empty.");
        }
    }
}
