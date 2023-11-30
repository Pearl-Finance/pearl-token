// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {CrossChainToken} from "@tangible/tokens/CrossChainToken.sol";
import {OFTUpgradeable} from "@tangible/layerzero/token/oft/v1/OFTUpgradeable.sol";

import {BytesLib} from "@layerzerolabs/contracts/libraries/BytesLib.sol";

import {IVotingEscrow} from "../interfaces/IVotingEscrow.sol";

/**
 * @title Pearl Contract
 * @author SeaZarrgh
 * @notice Pearl is an upgradeable, cross-chain fungible token designed for decentralized finance (DeFi) applications. It
 * extends CrossChainToken and OFTUpgradeable to facilitate token operations across multiple blockchain networks. The
 * contract is UUPS-upgradeable, allowing for future improvements or fixes.
 *
 * @dev The contract uses a unique storage pattern to separate its storage from the inherited contracts, ensuring safer
 * upgrades and better maintainability.
 *
 *      Key features include:
 *      - An upgradeable token contract that adheres to EIP-20 standards.
 *      - Integration with LayerZero's cross-chain messaging for token transfers across different blockchains.
 *      - A specialized mechanism for minting and burning tokens, with restrictions based on the token's main chain
 *        status.
 *      - Support for minting tokens into a voting escrow (VE) contract, enabling DeFi governance features.
 *      - Events for tracking cross-chain token minting activities.
 *      - Custom error messages for enhanced clarity and debugging.
 *
 * The contract structure is modular, with a focus on security, gas efficiency, and upgradeability.
 */
contract Pearl is CrossChainToken, OFTUpgradeable, UUPSUpgradeable {
    using BytesLib for bytes;
    using SafeERC20 for IERC20;

    uint16 private constant PT_SEND_VE = 1;

    /// @custom:storage-location erc7201:pearl.storage.Pearl
    struct PearlStorage {
        address _votingEscrow;
        address minter;
    }

    // keccak256(abi.encode(uint256(keccak256("pearl.storage.Pearl")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant PearlStorageLocation = 0x2211542a1178bd3eaa07c37839f7a3e0804a0f0ced34b6c6b5a4d67d9a8cf800;

    function _getPearlStorage() private pure returns (PearlStorage storage $) {
        // slither-disable-next-line assembly
        assembly {
            $.slot := PearlStorageLocation
        }
    }

    event ReceiveVEFromChain(
        uint16 indexed _srcChainId,
        address indexed to,
        uint256 indexed srcTokenId,
        uint256 tokenId,
        uint256 amount,
        uint256 vestingDuration
    );

    error NotAuthorized(address caller);
    error UnsupportedChain(uint256 chainId);
    error ValueUnchanged();

    /**
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor(uint256 mainChainId, address endpoint) CrossChainToken(mainChainId) OFTUpgradeable(endpoint) {
        _disableInitializers();
    }

    /**
     * @notice Authorizes a new implementation contract for an upgrade.
     * @dev This function is an override of the `_authorizeUpgrade` function from the UUPSUpgradeable contract. It
     * restricts the upgrade functionality to the owner of the contract only. The function checks that the caller is the
     * owner before proceeding with the upgrade. This is a critical security feature to prevent unauthorized upgrades.
     * @param newImplementation The address of the new contract implementation to be upgraded to.
     * @custom:security-note Ensure that the `newImplementation` address is a trusted and properly audited contract to
     * avoid security risks.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @notice Initializes the Pearl contract with a given voting escrow address.
     * @dev This function initializes the contract, sets the initial minter to the sender, and links the voting escrow
     * contract. It should be called only once right after the deployment of the contract. The function is marked as an
     * initializer to prevent its re-execution. Inherits the `__OFT_init` function from the OFTUpgradeable contract for
     * basic token setup.
     * @param votingEscrow The address of the voting escrow (VE) contract to be associated with this token.
     */
    function initialize(address votingEscrow) external initializer {
        __OFT_init(msg.sender, "Pearl", "PEARL");
        PearlStorage storage $ = _getPearlStorage();
        $.minter = msg.sender;
        $._votingEscrow = votingEscrow;
    }

    /**
     * @notice Sets or updates the minter address.
     * @dev Updates the minter address in the PearlStorage. This function can only be called by the contract owner. The
     * minter is responsible for minting new tokens. If the new minter address is the same as the current one, the
     * function will revert to avoid unnecessary state changes and potential gas costs.
     * @param _minter The address to be set as the new minter. It should be a trusted address with minting privileges.
     * @custom:error ValueUnchanged Indicates that the new minter address is the same as the current one.
     */
    function setMinter(address _minter) external onlyOwner {
        PearlStorage storage $ = _getPearlStorage();
        if ($.minter == _minter) {
            revert ValueUnchanged();
        }
        $.minter = _minter;
    }

    /**
     * @notice Mints new tokens to a specified address.
     * @dev This function allows the minter to create new tokens. It can only be executed on the main chain, as verified
     * by `isMainChain`. The function checks if the sender is the minter and if the contract is on the main chain. If
     * either of these conditions is not met, the function will revert with an appropriate error. This is to ensure that
     * minting only occurs under authorized and intended circumstances.
     * @param to The address that will receive the newly minted tokens. Must be a valid address.
     * @param amount The amount of tokens to be minted.
     * @custom:error NotAuthorized Indicates that the caller is not authorized to mint tokens (not the minter).
     * @custom:error UnsupportedChain Indicates that the minting attempt is made on a non-main chain.
     */
    function mint(address to, uint256 amount) external {
        PearlStorage storage $ = _getPearlStorage();
        if (msg.sender == $.minter) {
            if (!isMainChain) {
                revert UnsupportedChain(block.chainid);
            }
        } else {
            revert NotAuthorized(msg.sender);
        }
        _mint(to, amount);
    }

    /**
     * @notice Burns a specified amount of tokens from a given address.
     * @dev Allows tokens to be burnt from the specified address. If the 'from' address is not the message sender, the
     * function will attempt to spend the allowance of the sender for the 'from' address. This provides a mechanism to
     * burn tokens on behalf of another address, given sufficient allowance. The function checks and updates the
     * allowances accordingly before proceeding with the burn operation.
     * @param from The address from which the tokens will be burnt. Can be the sender or another address with an
     * allowance.
     * @param amount The amount of tokens to burn. Must be less than or equal to the balance of the 'from' address.
     */
    function burn(address from, uint256 amount) external {
        if (from != msg.sender) {
            _spendAllowance(from, msg.sender, amount);
        }
        _burn(from, amount);
    }

    /**
     * @notice Retrieves the current minter address.
     * @dev Returns the address designated as the minter, which is stored in the PearlStorage. The minter is the address
     * with the authority to mint new tokens. This function provides a view method to access this information.
     * @return The address currently assigned as the minter.
     */
    function minter() external view returns (address) {
        return _getPearlStorage().minter;
    }

    /**
     * @notice Handles incoming cross-chain messages and executes corresponding actions.
     * @dev This function is an override of the `_nonblockingLzReceive` function from the OFTUpgradeable contract. It
     * processes incoming messages from LayerZero's cross-chain communication. Specifically, it handles messages of type
     * `PT_SEND_VE` to mint voting escrow tokens. If the packet type is not `PT_SEND_VE`, it delegates the processing to
     * the parent contract. The function asserts that this contract is on the main chain before processing `PT_SEND_VE`
     * messages.
     * @param srcChainId The source chain ID from which the message is sent.
     * @param srcAddress The source address in the originating chain, encoded in bytes.
     * @param nonce A unique identifier for the message.
     * @param payload The payload of the message, containing the data necessary for processing.
     */
    function _nonblockingLzReceive(uint16 srcChainId, bytes memory srcAddress, uint64 nonce, bytes memory payload)
        internal
        virtual
        override
    {
        uint16 packetType;

        // slither-disable-next-line assembly
        assembly {
            packetType := mload(add(payload, 32))
        }

        if (packetType == PT_SEND_VE) {
            assert(isMainChain);
            _sendVotingEscrowAck(srcChainId, srcAddress, nonce, payload);
        } else {
            super._nonblockingLzReceive(srcChainId, srcAddress, nonce, payload);
        }
    }

    /**
     * @notice Processes the voting escrow token minting from a cross-chain message.
     * @dev This internal function is called by `_nonblockingLzReceive` to handle `PT_SEND_VE` packet types. It decodes
     * the payload to extract the necessary information and mints voting escrow tokens accordingly. The function assumes
     * that it is always called in the context of a valid cross-chain message. Emits a `ReceiveVEFromChain` event upon
     * successful minting of the voting escrow tokens.
     * @param srcChainId The source chain ID from which the voting escrow token minting request originated.
     * @param payload The payload containing the minting request details, such as recipient address, amount, and vesting
     * duration.
     */
    function _sendVotingEscrowAck(uint16 srcChainId, bytes memory, uint64, bytes memory payload) internal virtual {
        (, bytes memory toAddressBytes, uint256 tokenId, uint256 amount, uint256 vestingDuration) =
            abi.decode(payload, (uint16, bytes, uint256, uint256, uint256));

        address to = toAddressBytes.toAddress(0);
        address ve = _getPearlStorage()._votingEscrow;

        _approve(address(this), ve, amount, false);
        uint256 _tokenId = IVotingEscrow(ve).mint(to, amount, vestingDuration);

        emit ReceiveVEFromChain(srcChainId, to, tokenId, _tokenId, amount, vestingDuration);
    }
}
