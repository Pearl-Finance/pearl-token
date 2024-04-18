// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

import "../src/utils/StringUtils.sol";

contract StringUtilsHelper {
    function convertDurationToString(uint256 duration, string memory _default) external pure returns (string memory) {
        return StringUtils.convertDurationToString(duration, _default);
    }

    function formatUintToString(uint256 value, uint256 decimals) external pure returns (string memory) {
        return StringUtils.formatUintToString(value, decimals);
    }
}

contract StringUtilsTest is Test {
    StringUtilsHelper helper;

    function setUp() public {
        helper = new StringUtilsHelper();
    }

    function test_convertDurationToString() public {
        _compareStrings(helper.convertDurationToString(30, ""), "< 1 minute");
        _compareStrings(helper.convertDurationToString(1 days, ""), "1 day");
        _compareStrings(helper.convertDurationToString(1 days + 20 hours, ""), "1 day, 20 hours");
        _compareStrings(helper.convertDurationToString(1 days + 20 hours, ""), "1 day, 20 hours");
        _compareStrings(helper.convertDurationToString(1 days + 20 hours + 5 minutes, ""), "1 day, 20 hours");
        _compareStrings(helper.convertDurationToString(1 days + 5 minutes, ""), "1 day");
        _compareStrings(helper.convertDurationToString(20 hours + 5 minutes, ""), "20 hours, 5 minutes");
        _compareStrings(helper.convertDurationToString(20 hours + 5, ""), "20 hours");
        _compareStrings(helper.convertDurationToString(20 minutes + 5, ""), "20 minutes");
        _compareStrings(helper.convertDurationToString(0, "DONE"), "DONE");
    }

    function test_formatUintToString() public {
        _compareStrings(helper.formatUintToString(0, 0), "0");
        _compareStrings(helper.formatUintToString(0, 1), "0");

        _compareStrings(helper.formatUintToString(1, 0), "1");
        _compareStrings(helper.formatUintToString(1, 1), "0.1");
        _compareStrings(helper.formatUintToString(1, 2), "0.01");
        _compareStrings(helper.formatUintToString(1, 3), "0.001");

        _compareStrings(helper.formatUintToString(123456789, 0), "123456789");
        _compareStrings(helper.formatUintToString(123456789, 1), "12345678.9");
        _compareStrings(helper.formatUintToString(123456789, 2), "1234567.89");
        _compareStrings(helper.formatUintToString(123456789, 3), "123456.789");

        _compareStrings(helper.formatUintToString(7890, 0), "7890");
        _compareStrings(helper.formatUintToString(7890, 1), "789");
        _compareStrings(helper.formatUintToString(7890, 2), "78.9");
        _compareStrings(helper.formatUintToString(7890, 3), "7.89");
        _compareStrings(helper.formatUintToString(7890, 4), "0.789");
        _compareStrings(helper.formatUintToString(7890, 5), "0.0789");
    }

    function _compareStrings(string memory str1, string memory str2) private {
        bytes32 hash1 = keccak256(bytes(str1));
        bytes32 hash2 = keccak256(bytes(str2));
        assertEq(hash1, hash2);
    }
}
