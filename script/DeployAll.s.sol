// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// FOUNDRY_PROFILE=optimized forge script ./script/DeployAll.s.sol --legacy --broadcast
contract DeployAll is DeployAllBase {
    function _getLegacyPearlAddress() internal pure override returns (address) {
        return 0x7238390d5f6F64e67c3211C343A410E2A3DEc142;
    }

    function _getLegacyVEPearlAddress() internal pure override returns (address) {
        return 0x017A26B18E4DA4FE1182723a39311e67463CF633;
    }

    function _getVoterAddress() internal pure override returns (address) {
        revert("DeployAll: voter address not set");
    }

    function _getPearlMinterAddress() internal pure override returns (address) {
        revert("DeployAll: minter address not set");
    }

    function _getMainChainAlias() internal pure override returns (string memory) {
        return "real";
    }

    function _getMigrationChainAlias() internal pure override returns (string memory) {
        return "polygon";
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = "real";
        aliases[1] = "arbitrum_one";
    }
}
