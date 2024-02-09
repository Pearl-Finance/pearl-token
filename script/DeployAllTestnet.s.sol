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
        return 0x043A0D1c7bfb60A9716ECF62F7BAd1c7F0c099a8;
    }

    function _getVoterAddress() internal pure override returns (address) {
        return 0xfeCdBDD83fe11b9d471971250F784BC0c85Ce48F;
    }

    function _getMainChainAlias() internal pure override returns (string memory) {
        return "unreal";
    }

    function _getMigrationChainAlias() internal pure override returns (string memory) {
        return "polygon_mumbai";
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = _getMainChainAlias();
        aliases[1] = "goerli";
    }
}
