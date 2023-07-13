// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";

contract BridgeNFT is BeaconProxy {
    constructor(address beacon, bytes memory data) BeaconProxy(beacon, data) {}
}
