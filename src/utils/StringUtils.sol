// SPDX-License-Identifier: MIT
pragma solidity =0.8.20;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title String Utilities
 * @author SeaZarrgh
 * @dev A library providing utility functions for string manipulation, particularly focused on numeric conversions and
 * formatting.
 * This library leverages OpenZeppelin's `Strings` library for efficient string operations. It offers functions to:
 * - Convert durations (in seconds) to human-readable string formats.
 * - Format uint256 values to string representations, considering decimal places, and efficiently manage trailing zeros.
 * - Internally, it includes helper functions for quantifying numeric values into readable strings and manipulating
 *   strings for formatting purposes.
 * The library is designed for internal use within contracts to assist in representing numerical data in a more readable
 * format for end-users.
 */
library StringUtils {
    using Strings for uint256;

    /**
     * @notice Converts a given duration in seconds to a human-readable string format.
     * @dev This function breaks down the total duration into days, hours, and minutes, and constructs a string
     * representation. If the duration includes days, it will format it as 'X day(s), Y hour(s)'. If it only includes
     * hours, as 'X hour(s), Y minute(s)', and so on. If the duration is zero, a default string provided by the caller
     * is returned. The conversion handles singular and plural forms of time units (day, hour, minute) for readability.
     * @param duration The duration in seconds to convert.
     * @param _default The default string to return if the duration is 0.
     * @return A string representing the human-readable format of the duration.
     */
    function convertDurationToString(uint256 duration, string memory _default) internal pure returns (string memory) {
        uint256 _days = duration / 86400;
        uint256 _hours = (duration % 86400) / 3600;
        uint256 _minutes = (duration % 3600) / 60;

        bytes memory dayPart = quantify(_days, "day");
        bytes memory hourPart = quantify(_hours, "hour");
        bytes memory minutePart = quantify(_minutes, "minute");

        if (dayPart.length != 0) {
            return string(hourPart.length != 0 ? abi.encodePacked(dayPart, ", ", hourPart) : dayPart);
        } else if (hourPart.length != 0) {
            return string(minutePart.length != 0 ? abi.encodePacked(hourPart, ", ", minutePart) : hourPart);
        } else if (minutePart.length != 0) {
            return string(minutePart);
        }

        return _default;
    }

    /**
     * @dev Generates a string representation for a numeric amount and its corresponding unit. This function is designed
     * to assist in creating readable time formats (like days, hours, minutes) by attaching the correct unit and
     * handling plural forms. For example, it will convert 1 'day' to '1 day' and 2 'day' to '2 days'. If the amount is
     * zero, it returns an empty string, as zero quantities are usually omitted in the final human-readable format.
     * @param amount The numeric amount to be converted to string format.
     * @param unit The unit associated with the amount, such as 'day', 'hour', 'minute'.
     * @return A string representation of the amount and unit, correctly formatted for singular or plural forms.
     */
    function quantify(uint256 amount, string memory unit) private pure returns (bytes memory) {
        if (amount == 0) {
            return bytes("");
        }
        return abi.encodePacked(amount.toString(), " ", unit, amount != 1 ? "s" : "");
    }

    /**
     * @notice Formats a uint256 value into a string representation, considering decimal places.
     * @dev This function divides the `uint256` value into its main and decimal parts based on the specified decimal
     * places. It efficiently handles the conversion and removes unnecessary trailing zeros in the decimal part. If the
     * decimal part is zero, the function returns the string representation of the main value only. This function is
     * useful for representing token amounts or other numerical values in a human-readable format, especially when
     * dealing with decimals.
     * @param value The `uint256` value to be formatted into a string.
     * @param decimals The number of decimal places to consider in the `uint256` value.
     * @return A string representation of the `uint256` value, formatted with the specified number of decimal places.
     */
    function formatUintToString(uint256 value, uint256 decimals) internal pure returns (string memory) {
        uint256 mainValue = value / (10 ** decimals);
        string memory mainStr = mainValue.toString();
        uint256 decimalValue = value % (10 ** decimals);
        // return early if decimal value is 0
        if (decimalValue == 0) {
            return mainStr;
        }
        string memory decimalStr = decimalValue.toString();
        decimalStr = padWithZeros(decimalStr, decimals);
        decimalStr = removeTrailingZeros(decimalStr);
        return string(abi.encodePacked(mainStr, ".", decimalStr));
    }

    /**
     * @dev Pads a given string with leading zeros up to a specified length. This function is primarily used in
     * formatting decimal parts of numbers where leading zeros are significant. For instance, converting '123' into
     * '00123' for a decimal length of 5. It's essential in ensuring numerical strings have consistent lengths,
     * especially after operations like modulus with decimals.
     * @param str The string to be padded with leading zeros.
     * @param decimals The target length of the string after padding.
     * @return A new string that is padded with leading zeros to match the specified length.
     */
    function padWithZeros(string memory str, uint256 decimals) private pure returns (string memory) {
        uint256 strLength = bytes(str).length;
        while (strLength < decimals) {
            str = string(abi.encodePacked("0", str));
            unchecked {
                ++strLength;
            }
        }
        return str;
    }

    /**
     * @dev Removes trailing zeros from a numeric string. This function is particularly useful in formatting numbers
     * where trailing zeros are not significant, such as in decimal parts of a formatted number. For example, it
     * converts '12300' to '123' by removing the non-significant zeros at the end. This ensures that the numerical
     * strings are concise and accurately represent the value without unnecessary padding.
     * @param str The numeric string from which to remove trailing zeros.
     * @return A new string representing the original number with trailing zeros removed.
     */
    function removeTrailingZeros(string memory str) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        uint256 strLength = strBytes.length;
        while (strLength > 0 && strBytes[strLength - 1] == "0") {
            unchecked {
                --strLength;
            }
        }
        return substring(strBytes, 0, strLength);
    }

    /**
     * @dev Extracts a substring from a given string based on start and end indices. This function is useful in string
     * manipulation tasks where specific portions of a string are needed. For example, it can be used to extract a
     * portion of a numeric string during formatting operations. It handles the substring extraction safely by creating
     * a new bytes array and copying the relevant parts of the original string into it.
     * @param strBytes The bytes array of the original string from which to extract the substring.
     * @param startIndex The starting index (inclusive) of the substring in the original string.
     * @param endIndex The ending index (exclusive) of the substring in the original string.
     * @return A new string that is a substring of the original string, ranging from the start index to one before the
     * end index.
     */
    function substring(bytes memory strBytes, uint256 startIndex, uint256 endIndex)
        private
        pure
        returns (string memory)
    {
        bytes memory result = new bytes(endIndex - startIndex);
        uint256 j = 0;
        for (uint256 i = startIndex; i < endIndex;) {
            bytes(result)[j] = strBytes[i];
            unchecked {
                ++i;
                ++j;
            }
        }
        return string(result);
    }
}
