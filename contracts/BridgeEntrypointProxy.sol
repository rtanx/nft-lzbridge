// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract BridgeEntrypointProxy is ERC1967Proxy {
    constructor(address implementationAddress, bytes memory initData) ERC1967Proxy(implementationAddress, initData) {}
}
