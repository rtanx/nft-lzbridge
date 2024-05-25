// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

contract BridgeStorage {
    struct TransferData {
        // Address of the original token. Left-zero-padded if shorter than 32 bytes
        address tokenAddress;
        // Lz chain ID of the token
        uint16 tokenChainId;
        // Symbol of the token
        bytes32 symbol;
        // Name of the token
        bytes32 name;
        // TokenID of the token
        uint256 tokenId;
        // URI of the token metadata (UTF-8)
        string uri;
        // Address of the recipient. Left-zero-padded if shorter than 32 bytes
        address recipientAddress;
        // Chain ID of the recipient
        // uint16 recipientChainId;
        // Sender address (on source chain)
        // bytes32 senderAddress;
        // Sender chainId (on source chain)
        // uint16 senderChainId;
    }

    struct State {
        // Mapping of bridge contracts on other chains
        mapping(uint16 => bytes32) bridgeImplementations;
        // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
        mapping(uint16 => mapping(bytes32 => address)) wrappedAssets;
        // Mapping to safely identify wrapped assets
        mapping(address => bool) isWrappedAsset;
    }
}

contract BridgeState {
    BridgeStorage.State _state;
}
