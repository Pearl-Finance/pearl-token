// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {DeployAllBase} from "./base/DeployAllBase.sol";

// FOUNDRY_PROFILE=optimized forge script ./script/DeployAllTestnet.s.sol --legacy --broadcast
contract DeployAllTestnet is DeployAllBase {
    function _getLegacyPearlAddress() internal pure override returns (address) {
        return 0x607Ed4f1296C800b3ABCb82Af24Ef382BdA1B181;
    }

    function _getLegacyVEPearlAddress() internal pure override returns (address) {
        return 0x4735cf16f00DFaDa85D313bE3E2bd39B04522b69;
    }

    function _getPearlMinterAddress() internal pure override returns (address) {
        return 0x80D1e7Be1475f9978F6E8D909d96b93a760FbBBb;
    }

    function _getVoterAddress() internal pure override returns (address) {
        return 0x0F5f036f75B8Cf772a97F8Df5902a448d60CDAeB;
    }

    function _getMainChainAlias() internal pure override returns (string memory) {
        return "unreal";
    }

    function _getMigrationChainAlias() internal pure override returns (string memory) {
        return "polygon_mumbai";
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](3);
        aliases[0] = _getMainChainAlias();
        aliases[1] = "sepolia";
        aliases[2] = "arbitrum_one_sepolia";
    }
}
