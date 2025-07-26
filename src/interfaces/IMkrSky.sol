// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IMkrSky {
    // Admin functions
    function rely(address usr) external;
    function deny(address usr) external;
    function file(bytes32 what, uint256 data) external;
    function collect(address to) external returns (uint256);
    function burn(uint256 skyAmt) external;

    // Public functions
    function mkrToSky(address usr, uint256 mkrAmt) external;

    // View functions
    function wards(address) external view returns (uint256);
    function fee() external view returns (uint256);
    function take() external view returns (uint256);
    function mkr() external view returns (address);
    function sky() external view returns (address);
    function rate() external view returns (uint256);
}
