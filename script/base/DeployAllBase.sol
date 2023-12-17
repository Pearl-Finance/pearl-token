// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {console} from "forge-std/Script.sol";

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

import {PearlDeploymentScript} from "./PearlDeploymentScript.sol";

import {Pearl} from "../../src/token/Pearl.sol";
import {VotingEscrow} from "../../src/governance/VotingEscrow.sol";
import {VotingEscrowVesting} from "../../src/governance/VotingEscrowVesting.sol";
import {VotingEscrowArtProxy} from "../../src/ui/VotingEscrowArtProxy.sol";
import {PearlMigrator} from "../../src/PearlMigrator.sol";

/**
 * @title Deployment Base Contract
 * @notice This abstract contract, extending PearlDeploymentScript, orchestrates the deployment of the Pearl ecosystem
 * across multiple blockchain networks. It automates the deployment and configuration of the Pearl and PearlMigrator
 * contracts, catering to both main and migration chains.
 * @dev The contract utilizes a series of internal and private functions to deploy and configure Pearl and PearlMigrator
 * contracts. These functions handle tasks such as determining chain aliases, computing proxy addresses, and deploying
 * contracts through proxies. The contract leverages LayerZero endpoints for cross-chain communication and deployment.
 *
 * Key Components:
 * - Automated deployment of Pearl and PearlMigrator using proxies.
 * - Chain-specific configurations for deployment and LayerZero endpoint interactions.
 * - Determination of main and migration chains for targeted deployment strategies.
 * - Use of internal and virtual functions that require implementation for specific deployment logic.
 *
 * The contract is designed for extensibility, allowing specific implementation details to be defined in derived
 * contracts, tailored to the unique requirements of different chain environments in the Pearl ecosystem.
 */
abstract contract DeployAllBase is PearlDeploymentScript {
    /**
     * @dev Coordinates the comprehensive deployment and configuration of the Pearl ecosystem across multiple blockchain
     * networks. This function is responsible for deploying the Pearl and PearlMigrator contracts and setting up
     * cross-chain communication.
     *
     * The deployment process involves:
     * 1. Setting up the deployment environment with `_setup`.
     * 2. Identifying the main and migration chain aliases.
     * 3. Initiating a fork based on the migration chain alias.
     * 4. Determining the total supply of the legacy Pearl contract for preminting in the new deployment.
     * 5. Broadcasting the deployment of the PearlMigrator contract.
     * 6. Iterating through deployment chain aliases to deploy or upgrade the Pearl contract.
     *    - On the main chain, deploys Pearl with premint amount and configures communication with PearlMigrator.
     *    - On other chains, deploys Pearl without the premint amount.
     * 7. Sets trusted remote addresses for the Pearl contract on each chain, enabling cross-chain interactions.
     *
     * This function ensures a synchronized and interconnected setup for the Pearl ecosystem, allowing for efficient
     * cross-chain functionality and uniform contract deployment across various networks.
     */
    function run() public {
        _setup();

        string memory mainChainAlias = _getMainChainAlias();
        string memory migrationChainAlias = _getMigrationChainAlias();

        vm.createSelectFork(_getMigrationChainAlias());

        uint256 premintAmount = IERC20(_getLegacyPearlAddress()).totalSupply();

        vm.startBroadcast(_pk);
        address migratorAddress = _deployMigrator();
        vm.stopBroadcast();

        string[] memory deploymentChainAliases = _getDeploymentChainAliases();

        for (uint256 i = 0; i < deploymentChainAliases.length; i++) {
            console.log("---");
            vm.createSelectFork(deploymentChainAliases[i]);
            vm.startBroadcast(_pk);
            Pearl pearl;
            if (keccak256(abi.encodePacked(deploymentChainAliases[i])) == keccak256(abi.encodePacked(mainChainAlias))) {
                address pearlAddress = _deployPearl(premintAmount);
                pearl = Pearl(pearlAddress);
                if (pearl.minter() != _getPearlMinterAddress()) {
                    pearl.setMinter(_getPearlMinterAddress());
                    console.log("Pearl minter set to %s", _getPearlMinterAddress());
                }
                if (
                    !pearl.isTrustedRemote(
                        _getLzChainId(migrationChainAlias), abi.encodePacked(migratorAddress, pearlAddress)
                    )
                ) {
                    pearl.setTrustedRemoteAddress(_getLzChainId(migrationChainAlias), abi.encodePacked(migratorAddress));
                }
                _deployVEPearl(pearlAddress);
            } else {
                address pearlAddress = _deployPearl();
                pearl = Pearl(pearlAddress);
            }
            for (uint256 j = 0; j < deploymentChainAliases.length; j++) {
                if (i != j) {
                    if (
                        !pearl.isTrustedRemote(
                            _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(address(pearl), address(pearl))
                        )
                    ) {
                        pearl.setTrustedRemoteAddress(
                            _getLzChainId(deploymentChainAliases[j]), abi.encodePacked(address(pearl))
                        );
                    }
                }
            }
            vm.stopBroadcast();
        }
    }

    /**
     * @dev Virtual function to be overridden in derived contracts to return the address of the legacy Pearl contract.
     * This address is used to determine the total supply for preminting in the new Pearl deployment.
     *
     * The implementation of this function in derived contracts should provide the specific address of the legacy Pearl
     * contract relevant to the deployment context.
     *
     * @return The address of the legacy Pearl contract.
     */
    function _getLegacyPearlAddress() internal pure virtual returns (address);

    function _getLegacyVEPearlAddress() internal pure virtual returns (address);

    function _getPearlMinterAddress() internal pure virtual returns (address);

    function _getVoterAddress() internal pure virtual returns (address);

    /**
     * @dev Virtual function to be overridden in derived contracts to return the alias of the main chain in the Pearl
     * ecosystem deployment. This alias is crucial for identifying the primary network where specific operations like
     * preminting will occur.
     *
     * Implementations in derived contracts should specify the chain alias that represents the main network in the
     * context of the Pearl ecosystem.
     *
     * @return A string representing the alias of the main chain.
     */
    function _getMainChainAlias() internal pure virtual returns (string memory);

    /**
     * @dev Virtual function to be overridden in derived contracts to specify the alias of the migration chain. This
     * chain alias is used to identify the network where the Pearl Migrator contract and other migration-related
     * operations are conducted.
     *
     * Implementations in derived contracts should provide the chain alias that corresponds to the network designated
     * for migration activities within the Pearl ecosystem.
     *
     * @return A string representing the alias of the migration chain.
     */
    function _getMigrationChainAlias() internal pure virtual returns (string memory);

    /**
     * @dev Virtual function to be overridden in derived contracts to provide an array of chain aliases where the Pearl
     * ecosystem will be deployed. This list is essential for ensuring the deployment and configuration of Pearl
     * contracts across multiple networks.
     *
     * Implementations in derived contracts should return an array of strings, each representing a chain alias for
     * deploying the Pearl ecosystem.
     *
     * @return aliases An array of strings representing the aliases of chains for deployment.
     */
    function _getDeploymentChainAliases() internal pure virtual returns (string[] memory aliases);

    /**
     * @dev Deploys the Pearl contract. This overloaded private function is used when no premint amount is required.
     * It calls the main `_deployPearl` function with a premint amount of zero.
     *
     * @return pearlProxy The address of the deployed Pearl proxy contract.
     */
    function _deployPearl() private returns (address pearlProxy) {
        pearlProxy = _deployPearl(0);
    }

    /**
     * @dev Deploys the Pearl contract with an option for preminting a specified amount. This function ensures
     * preminting occurs only during the first deployment, preventing it on subsequent deployments.
     *
     * The deployment process includes:
     * 1. Computing the expected Pearl contract address using CREATE2 for deterministic deployment.
     * 2. Checking if the proxy address for the Pearl contract is already deployed.
     *    - If deployed, sets the premint amount to zero to prevent double preminting.
     * 3. Deploying or retrieving the Pearl contract.
     * 4. Deploying a proxy for the Pearl contract and upgrading it if necessary.
     * 5. Preminting tokens to the Pearl contract address if premint amount is specified and it's the first deployment.
     *
     * @param premintAmount The amount of tokens to be preminted in the new Pearl deployment, applicable only during
     * the first deployment.
     * @return pearlProxy The address of the deployed or upgraded Pearl proxy contract.
     */
    function _deployPearl(uint256 premintAmount) private returns (address pearlProxy) {
        address lzEndpoint = _getLzEndpoint();
        uint256 mainChainId = getChain(_getMainChainAlias()).chainId;
        address pearlAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(type(Pearl).creationCode, abi.encode(mainChainId, lzEndpoint)))
        );

        (address pearlProxyAddress,) = _computeProxyAddress("Pearl");
        (address vePearlProxyAddress,) = _computeProxyAddress("vePearl");

        if (_isDeployed(pearlProxyAddress)) {
            premintAmount = 0;
        }

        Pearl pearl;

        if (_isDeployed(pearlAddress)) {
            console.log("Pearl is already deployed to %s", pearlAddress);
            pearl = Pearl(pearlAddress);
        } else {
            pearl = new Pearl{salt: _SALT}(mainChainId, lzEndpoint);
            assert(pearlAddress == address(pearl));
            console.log("Pearl deployed to %s", pearlAddress);
        }

        bytes memory init = abi.encodeWithSelector(Pearl.initialize.selector, vePearlProxyAddress);
        pearlProxy = _deployProxy("Pearl", pearlAddress, init);
        pearl = Pearl(pearlProxy);

        if (premintAmount != 0) {
            pearl.mint(pearlAddress, premintAmount);
        }
    }

    function _deployVEPearl(address pearlAddress) private returns (address vePearlProxy) {
        (address vePearlProxyAddress,) = _computeProxyAddress("vePearl");

        address artProxyAddress = _deployArtProxy();
        address vestingAddress = _deployVesting(vePearlProxyAddress);
        address voterAddress = _getVoterAddress();

        address vePearlAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(type(VotingEscrow).creationCode, abi.encode(pearlAddress)))
        );

        VotingEscrow vePearl;

        if (_isDeployed(vePearlAddress)) {
            console.log("VE Pearl is already deployed to %s", vePearlAddress);
            vePearl = VotingEscrow(vePearlAddress);
        } else {
            vePearl = new VotingEscrow{salt: _SALT}(pearlAddress);
            assert(vePearlAddress == address(vePearl));
            console.log("VE Pearl deployed to %s", vePearlAddress);
        }

        bytes memory init =
            abi.encodeWithSelector(VotingEscrow.initialize.selector, vestingAddress, voterAddress, artProxyAddress);
        vePearlProxy = _deployProxy("vePearl", vePearlAddress, init);
        vePearl = VotingEscrow(vePearlProxy);

        if (vePearl.artProxy() != artProxyAddress) {
            vePearl.setArtProxy(artProxyAddress);
            console.log("vePearl art proxy set to %s", artProxyAddress);
        }

        if (vePearl.voter() != voterAddress) {
            vePearl.setVoter(voterAddress);
            console.log("vePearl voter set to %s", voterAddress);
        }
    }

    function _deployArtProxy() internal returns (address artProxyAddress) {
        bytes32 initCodeHash = hashInitCode(type(VotingEscrowArtProxy).creationCode);
        bytes32 salt = keccak256(abi.encodePacked(_SALT, "VotingEscrowArtProxy"));
        artProxyAddress = vm.computeCreate2Address(salt, initCodeHash);

        if (!_isDeployed(artProxyAddress)) {
            VotingEscrowArtProxy artProxy = new VotingEscrowArtProxy{salt: salt}();
            assert(artProxyAddress == address(artProxy));
            console.log("VotingEscrowArtProxy deployed to %s", artProxyAddress);
        }
    }

    function _deployVesting(address vePearlAddress) internal returns (address vestingAddress) {
        vestingAddress = vm.computeCreate2Address(
            _SALT, keccak256(abi.encodePacked(type(VotingEscrowVesting).creationCode, abi.encode(vePearlAddress)))
        );

        VotingEscrowVesting vesting;

        if (_isDeployed(vestingAddress)) {
            console.log("VE Vesting is already deployed to %s", vestingAddress);
            vesting = VotingEscrowVesting(vestingAddress);
        } else {
            vesting = new VotingEscrowVesting{salt: _SALT}(vePearlAddress);
            assert(vestingAddress == address(vesting));
            console.log("VE Vesting deployed to %s", vestingAddress);
        }
    }

    /**
     * @dev Deploys the PearlMigrator contract. This function computes the PearlMigrator contract's address using
     * CREATE2 for deterministic deployment and deploys or upgrades the contract if necessary.
     *
     * The deployment process involves:
     * 1. Computing the expected PearlMigrator contract address.
     * 2. Checking if the contract is already deployed and either retrieves or deploys it.
     * 3. Deploys a proxy for the PearlMigrator contract and upgrades it if necessary.
     * 4. Initializes the contract with necessary parameters like LayerZero endpoint, legacy Pearl address, etc.
     *
     * @return migratorProxy The address of the deployed or upgraded PearlMigrator proxy contract.
     */
    function _deployMigrator() private returns (address migratorProxy) {
        address lzEndpoint = _getLzEndpoint();
        address legacyPearlAddress = _getLegacyPearlAddress();
        address legacyVEPearlAddress = _getLegacyVEPearlAddress();
        uint16 lzMainChainId = _getLzChainId(_getMainChainAlias());

        address migratorAddress = vm.computeCreate2Address(
            _SALT,
            keccak256(
                abi.encodePacked(
                    type(PearlMigrator).creationCode,
                    abi.encode(lzEndpoint, legacyPearlAddress, legacyVEPearlAddress, lzMainChainId)
                )
            )
        );

        PearlMigrator migrator;

        if (_isDeployed(migratorAddress)) {
            console.log("Pearl Migrator is already deployed to %s", migratorAddress);
            migrator = PearlMigrator(migratorAddress);
        } else {
            migrator =
            new PearlMigrator{salt: _SALT}(lzEndpoint, legacyPearlAddress, legacyVEPearlAddress, lzMainChainId);
            assert(migratorAddress == address(migrator));
            console.log("Pearl Migrator deployed to %s", migratorAddress);
        }
        bytes memory init = abi.encodeWithSelector(PearlMigrator.initialize.selector);
        migratorProxy = _deployProxy("PearlMigrator", migratorAddress, init);
    }

    /**
     * @dev Retrieves the LayerZero chain ID for a given chain alias. This function is essential for setting up
     * cross-chain communication parameters in the deployment process.
     *
     * The function maps common chain aliases to their respective LayerZero chain IDs. This mapping is crucial for
     * identifying the correct LayerZero endpoint for each chain involved in the deployment.
     *
     * @param chainAlias The alias of the chain for which the LayerZero chain ID is required.
     * @return The LayerZero chain ID corresponding to the given chain alias.
     * Reverts with 'Unsupported chain' if the alias does not match any known chains.
     */
    function _getLzChainId(string memory chainAlias) internal pure returns (uint16) {
        bytes32 chain = keccak256(abi.encodePacked(chainAlias));
        if (chain == keccak256("polygon")) {
            return 109;
        } else if (chain == keccak256("real")) {
            return 0; // TODO
        } else if (chain == keccak256("arbitrum_one")) {
            return 110;
        } else if (chain == keccak256("polygon_mumbai")) {
            return 10109;
        } else if (chain == keccak256("unreal")) {
            return 0; // TODO
        } else if (chain == keccak256("goerli")) {
            return 10121;
        } else {
            revert("Unsupported chain");
        }
    }

    /**
     * @dev Retrieves the LayerZero endpoint address for the current chain. This function is crucial for configuring the
     * LayerZero communication parameters for cross-chain functionalities.
     *
     * The function maps the current chain ID to its corresponding LayerZero endpoint address. These endpoints are
     * essential for enabling cross-chain interactions within the Pearl ecosystem.
     *
     * @return lzEndpoint The LayerZero endpoint address for the current chain. Reverts with an error if the current
     * chain is not supported or if the endpoint is not defined.
     */
    function _getLzEndpoint() internal returns (address lzEndpoint) {
        lzEndpoint = _getLzEndpoint(block.chainid);
    }

    /**
     * @dev Overloaded version of `_getLzEndpoint` that retrieves the LayerZero endpoint address for a specified chain
     * ID. This variation allows for more flexibility in targeting specific chains during the deployment process.
     *
     * @param chainId The chain ID for which the LayerZero endpoint address is required.
     * @return lzEndpoint The LayerZero endpoint address for the specified chain ID. Reverts with an error if the chain
     * ID does not have a defined endpoint.
     */
    function _getLzEndpoint(uint256 chainId) internal returns (address lzEndpoint) {
        if (chainId == getChain("polygon").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("real").chainId) {
            lzEndpoint = address(0); // TODO
        } else if (chainId == getChain("arbitrum_one").chainId) {
            lzEndpoint = 0x3c2269811836af69497E5F486A85D7316753cf62;
        } else if (chainId == getChain("polygon_mumbai").chainId) {
            lzEndpoint = 0xf69186dfBa60DdB133E91E9A4B5673624293d8F8;
        } else if (chainId == getChain("unreal").chainId) {
            lzEndpoint = address(0); // TODO
        } else if (chainId == getChain("goerli").chainId) {
            lzEndpoint = 0xbfD2135BFfbb0B5378b56643c2Df8a87552Bfa23;
        } else {
            revert("No LayerZero endpoint defined for this chain.");
        }
    }
}
