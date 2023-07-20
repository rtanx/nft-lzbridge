// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./token/WrappedERC721Implementation.sol";
import "@layerzerolabs/solidity-examples/contracts/util/BytesLib.sol";
import "./token/BridgeNFT.sol";
import "./BridgeState.sol";

contract LzNFTBridge is NonblockingLzApp, IERC721Receiver, BridgeState {
    using BytesLib for bytes;

    // Provider chainId where contract deployed
    uint16 public immutable lzChainId;

    uint256 defaultGasForDestinationLzReceive = 1000000;
    uint16 public immutable ADAPTER_PARAM_VERSION = 1;

    event TransferNFT(
        address tokenAddress,
        address senderAddress,
        address recipientAddress,
        uint16 senderChainId,
        uint16 recipientChainId,
        uint256 tokenId
    );

    event ReceiveNFT(
        address originalTokenAddress,
        address wrappedTokenAddress,
        address recipientAddress,
        uint256 tokenId,
        uint16 senderChainId,
        uint16 originalTokenChainId
    );

    constructor(uint16 _lzChainId, address _endpoint) NonblockingLzApp(_endpoint) {
        lzChainId = _lzChainId;
    }

    function onERC721Received(address operator, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/) external view returns (bytes4) {
        require(operator == address(this), "Can only bridge tokens via transferNFT method.");
        return IERC721Receiver.onERC721Received.selector;
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory /* _srcAddress */, uint64 /* _nonce */, bytes memory _payload) internal override {
        BridgeStorage.TransferData memory transferData = _parseTransferData(_payload);

        bytes32 identifier = keccak256(abi.encodePacked(transferData.recipientAddress, transferData.tokenAddress, transferData.tokenId));
        BridgeState.onHoldTransfer[_srcChainId][identifier] = _payload;
    }

    function redeemNFT(uint16 srcChain, address recipientAddress, address tokenAddress, uint256 tokenId) public {
        bytes32 identifier = keccak256(abi.encodePacked(recipientAddress, tokenAddress, tokenId));
        bytes memory payload = BridgeState.onHoldTransfer[srcChain][identifier];
        require(payload.length > 0, "No matching NFT transfer transactions");

        BridgeStorage.TransferData memory transferData = _parseTransferData(payload);
        require(transferData.recipientAddress == msg.sender, "Only the recipient can redeem");

        (, address wrappedToken) = _completeTransfer(transferData);
        emit ReceiveNFT(
            transferData.tokenAddress,
            wrappedToken,
            transferData.recipientAddress,
            transferData.tokenId,
            srcChain,
            transferData.tokenChainId
        );
    }

    function _completeTransfer(BridgeStorage.TransferData memory transferData) internal returns (bool isWrapped, address wrappedTokenAddress) {
        IERC721 token;
        if (transferData.tokenChainId == lzChainId) {
            token = IERC721(transferData.tokenAddress);
        } else {
            address wrapped = wrappedAsset(transferData.tokenChainId, addressToBytes32(transferData.tokenAddress));
            if (wrapped == address(0x0)) {
                wrapped = _createWrapped(
                    transferData.tokenChainId,
                    addressToBytes32(transferData.tokenAddress),
                    transferData.name,
                    transferData.symbol
                );
            }
            wrappedTokenAddress = wrapped;
            isWrapped = true;
            token = IERC721(wrapped);
        }

        if (transferData.tokenChainId != lzChainId) {
            WrappedERC721Implementation(address(token)).mint(transferData.recipientAddress, transferData.tokenId, transferData.uri);
        } else {
            token.safeTransferFrom(address(this), transferData.recipientAddress, transferData.tokenId);
        }
    }

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view returns (address) {
        return _state.wrappedAssets[tokenChainId][tokenAddress];
    }

    function setWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress, address wrapperAddress) internal {
        _state.wrappedAssets[tokenChainId][tokenAddress] = wrapperAddress;
        _state.isWrappedAsset[wrapperAddress] = true;
    }

    function _createWrapped(uint16 tokenChainId, bytes32 tokenAddress, bytes32 name, bytes32 symbol) internal returns (address token) {
        require(tokenChainId != lzChainId, "Can only wrap tokens from another EVMs chain");
        require(wrappedAsset(tokenChainId, tokenAddress) == address(0x0), "wrapped asset already exists");

        // init wrapped ERC721 Implementation
        bytes memory initArgs = abi.encodeWithSelector(
            WrappedERC721Implementation.initialize.selector,
            bytes32ToString(name),
            bytes32ToString(symbol),
            address(this),
            tokenChainId,
            tokenAddress
        );

        // init beacon proxy
        bytes memory constructorArgs = abi.encode(address(this), initArgs);

        bytes memory bytecode = abi.encodePacked(type(BridgeNFT).creationCode, constructorArgs);

        bytes32 salt = keccak256(abi.encodePacked(tokenChainId, tokenAddress));

        assembly {
            token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            let ext_code_size := extcodesize(token)

            if iszero(extcodesize(ext_code_size)) {
                revert(0, 0)
            }

            extcodecopy(token, 0, 0, 1)

            if iszero(mload(0)) {
                let revert_size := sub(ext_code_size, 1)
                extcodecopy(token, 0, 1, revert_size)
                revert(0, revert_size)
            }
        }
        require(token != address(0x0), "Failed creating wrappen token contract");
        setWrappedAsset(tokenChainId, tokenAddress, token);
    }

    function _parseTransferData(bytes memory payload) internal pure returns (BridgeStorage.TransferData memory) {
        BridgeStorage.TransferData memory transferData;
        (
            transferData.tokenAddress,
            transferData.tokenChainId,
            transferData.symbol,
            transferData.name,
            transferData.tokenId,
            transferData.uri,
            transferData.recipientAddress
        ) = abi.decode(payload, (address, uint16, bytes32, bytes32, uint256, string, address));
        return transferData;
    }

    /// @notice Crosschain transfer ERC721 token
    /// @dev Send the information of asset packed into to destination chain for generating wrapped asset in destination chain
    /// @param token A current chain NFT token address
    /// @param tokenId A tokenId to transfer
    /// @param recipientChainId The destination receipent lz chainId
    /// @param recipientDestAddress a wallet address of recipient in destination chain
    function transferNFT(address token, uint256 tokenId, uint16 recipientChainId, address recipientDestAddress) public payable {
        BridgeStorage.TransferData memory transferData;

        if (_state.isWrappedAsset[token]) {
            // if it's wrapper asset, then retrive the original token chainId
            transferData.tokenChainId = WrappedERC721Implementation(token).chainId();
            // get the native contract address
            transferData.tokenAddress = bytes32ToAddress(WrappedERC721Implementation(token).nativeContract());
        } else {
            transferData.tokenChainId = lzChainId;
            transferData.tokenAddress = token;
            require(ERC165(token).supportsInterface(type(IERC721).interfaceId), "token must support the ERC721 interface");
            require(ERC165(token).supportsInterface(type(IERC721Metadata).interfaceId), "must support the ERC721-Metadata extension");
        }

        (transferData.symbol, transferData.name, transferData.uri) = _retrieveMetadata(token, tokenId);

        IERC721(token).safeTransferFrom(_msgSender(), address(this), tokenId);
        if (transferData.tokenChainId != lzChainId) {
            WrappedERC721Implementation(token).burn(tokenId);
        }
        transferData.tokenId = tokenId;
        transferData.recipientAddress = recipientDestAddress;

        _transferNFT(transferData, recipientChainId);

        emit TransferNFT(token, _msgSender(), recipientDestAddress, lzChainId, recipientChainId, tokenId);
    }

    function _transferNFT(BridgeStorage.TransferData memory transfer, uint16 recipientChainId) internal {
        bytes memory payload = _encodeTransferData(transfer);

        bytes memory adapterParams = abi.encodePacked(ADAPTER_PARAM_VERSION, defaultGasForDestinationLzReceive);

        (uint256 estimatedFee, ) = lzEndpoint.estimateFees(recipientChainId, address(this), payload, false, adapterParams);
        require(msg.value >= estimatedFee, "Not enough payable value to cover gas fee in destination address");

        _lzSend(recipientChainId, payload, payable(_msgSender()), address(0x0), adapterParams, msg.value);
    }

    function _retrieveMetadata(address tokenAddress, uint256 tokenId) internal view returns (bytes32 symbol, bytes32 name, string memory uri) {
        (, bytes memory queriedSymbol) = tokenAddress.staticcall(abi.encodeWithSignature("symbol()"));
        (, bytes memory queriedName) = tokenAddress.staticcall(abi.encodeWithSignature("name()"));
        (, bytes memory queriedUri) = tokenAddress.staticcall(abi.encodeWithSignature("tokenURI(uint256)", tokenId));
        string memory symbolString = abi.decode(queriedSymbol, (string));
        string memory nameString = abi.decode(queriedName, (string));
        uri = abi.decode(queriedUri, (string));

        assembly {
            // first 32 bytes hold string length
            // mload then loads the next word, i.e. the first 32 bytes of the strings
            // NOTE: this means that we might end up with an
            // invalid utf8 string (e.g. if we slice an emoji in half).  The VAA
            // payload specification doesn't require that these are valid utf8
            // strings, and it's cheaper to do any validation off-chain for
            // presentation purposes
            symbol := mload(add(symbolString, 32))
            name := mload(add(nameString, 32))
        }
    }

    function _encodeTransferData(BridgeStorage.TransferData memory transfer) internal pure returns (bytes memory) {
        bytes memory encoded = abi.encodePacked(
            transfer.tokenAddress,
            transfer.tokenChainId,
            transfer.symbol,
            transfer.name,
            transfer.tokenId,
            transfer.uri,
            transfer.recipientAddress
        );
        return encoded;
    }

    function setDefaultGasForDestinationLzReceive(uint256 _price) external onlyOwner {
        defaultGasForDestinationLzReceive = _price;
    }

    // ------------------ HELPERS --------------------
    function bytes32ToString(bytes32 b) internal pure returns (string memory) {
        uint256 i;
        while (i < 32 && b[i] != 0) {
            i++;
        }
        bytes memory arr = new bytes(i);
        for (uint c = 0; c < i; c++) {
            arr[c] = b[c];
        }
        return string(arr);
    }

    function bytes32ToAddress(bytes32 b) internal pure returns (address) {
        return address(uint160(uint256(b)));
    }

    function addressToBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }
    // ------------------ END HELPERS ----------------
}
