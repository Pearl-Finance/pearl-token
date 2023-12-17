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
        return 0xa9a9138cf74d11B9fda97ea7aFA9425c62d2E939;
    }

    function _getVoterAddress() internal pure override returns (address) {
        return 0x39edC43746EA76B973B463Fd76C65923b1CB1042;
    }

    function _getMainChainAlias() internal pure override returns (string memory) {
        return "unreal";
    }

    function _getMigrationChainAlias() internal pure override returns (string memory) {
        return "polygon_mumbai";
    }

    function _getDeploymentChainAliases() internal pure override returns (string[] memory aliases) {
        aliases = new string[](2);
        aliases[0] = "unreal";
        aliases[1] = "goerli";
    }
}
