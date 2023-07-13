// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// import "@layerzerolabs/solidity-examples/contracts/token/onft/extension/ProxyONFT721.sol";
import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./token/WrappedERC721Implementation.sol";
import "@layerzerolabs/solidity-examples/contracts/util/BytesLib.sol";
import "./token/BridgeNFT.sol";

contract RankerDaoBridge is NonblockingLzApp, IERC721Receiver {
    using BytesLib for bytes;

    // Mapping of bridge contracts on other chains
    mapping(uint16 => bytes32) bridgeImplementations;

    // Mapping of wrapped assets (chainID => nativeAddress => wrappedAddress)
    mapping(uint16 => mapping(bytes32 => address)) wrappedAssets;

    // Mapping to safely identify wrapped assets
    mapping(address => bool) isWrappedAsset;

    // Provider chainId where contract deployed
    uint16 public immutable lzChainId;

    struct TransferData {
        // Address of the original token. Left-zero-padded if shorter than 32 bytes
        bytes32 tokenAddress;
        // Address of the wrapped token from sender chain. Left-zero-padded if shorter than 32 bytes
        // value would be address(0x0) if the source chain is where the original token live (token not wrapped previously)
        bytes32 srcChainWrappedTokenAddress;
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
        bytes32 recipientAddress;
        // Chain ID of the recipient
        uint16 recipientChainId;
        // Sender address (on source chain)
        bytes32 senderAddress;
        // Chain ID of the sender
        uint16 senderChainId;
    }

    event TransferNFT(
        address originalTokenAddress,
        address inChainWrappedTokenAddress,
        address senderAddress,
        address recipientAddress,
        uint16 originalTokenChainId,
        uint16 senderChainId,
        uint16 recipientChainId,
        uint256 tokenId
    );

    event ReceiveNFT(
        address originalTokenAddress,
        address wrappedTokenAddress,
        address sourceChainWrappedTokenAddress,
        address senderAddress,
        address recipientAddress,
        uint256 tokenId,
        uint16 senderChainId,
        uint16 originalTokenChainId
    );

    constructor(address _endpoint) NonblockingLzApp(_endpoint) {
        lzChainId = lzEndpoint.getChainId();
    }

    function onERC721Received(address operator, address /*from*/, uint256 /*tokenId*/, bytes calldata /*data*/) external view returns (bytes4) {
        require(operator == address(this), "Can only bridge tokens via transferNFT method.");
        return IERC721Receiver.onERC721Received.selector;
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory /* _srcAddress */, uint64 /* _nonce */, bytes memory _payload) internal override {
        TransferData memory transferData = _parseTransferData(_payload);
        require(lzChainId == transferData.recipientChainId, "Invalid target chain");
        require(transferData.senderChainId == _srcChainId, "Invalid source chain, doesn't match with source chain of token being transferred");

        _completeTransfer(transferData);
    }

    function _completeTransfer(TransferData memory transferData) internal {
        IERC721 token;
        address wrappedTokenAddress;
        if (transferData.tokenChainId == lzChainId) {
            token = IERC721(bytes32ToAddress(transferData.tokenAddress));
        } else {
            address wrapped = wrappedAsset(transferData.tokenChainId, transferData.tokenAddress);

            if (wrapped == address(0x0)) {
                wrapped = _createWrapped(transferData.tokenChainId, transferData.tokenAddress, transferData.name, transferData.symbol);
            }
            wrappedTokenAddress = wrapped;
            token = IERC721(wrapped);
        }

        address transferRecipient = bytes32ToAddress(transferData.recipientAddress);

        if (transferData.tokenChainId != lzChainId) {
            WrappedERC721Implementation(address(token)).mint(transferRecipient, transferData.tokenId, transferData.uri);
        } else {
            token.safeTransferFrom(address(this), transferRecipient, transferData.tokenId);
        }
        emit ReceiveNFT(
            bytes32ToAddress(transferData.tokenAddress),
            address(token),
            bytes32ToAddress(transferData.srcChainWrappedTokenAddress),
            bytes32ToAddress(transferData.senderAddress),
            transferRecipient,
            transferData.tokenId,
            transferData.senderChainId,
            transferData.tokenChainId
        );
    }

    function wrappedAsset(uint16 tokenChainId, bytes32 tokenAddress) public view returns (address) {
        return wrappedAssets[tokenChainId][tokenAddress];
    }

    function setWrappedAsset(uint16 tokenChainId, bytes32 tokenAddress, address wrapperAddress) internal {
        wrappedAssets[tokenChainId][tokenAddress] = wrapperAddress;
        isWrappedAsset[wrapperAddress] = true;
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

            if iszero(extcodesize(token)) {
                revert(0, 0)
            }
        }
        setWrappedAsset(tokenChainId, tokenAddress, token);
    }

    function _parseTransferData(bytes memory payload) internal pure returns (TransferData memory) {
        TransferData memory transferData;
        (
            transferData.tokenAddress,
            transferData.srcChainWrappedTokenAddress,
            transferData.tokenChainId,
            transferData.symbol,
            transferData.name,
            transferData.tokenId,
            transferData.uri,
            transferData.recipientAddress,
            transferData.recipientChainId
        ) = abi.decode(payload, (bytes32, bytes32, uint16, bytes32, bytes32, uint256, string, bytes32, uint16));
        return transferData;
    }

    /// @notice Crosschain transfer ERC721 token
    /// @dev Send the information of asset packed into to destination chain for generating wrapped asset in destination chain
    /// @param token A current chain NFT token address
    /// @param tokenId A tokenId to transfer
    /// @param recipientChainId The destination receipent lz chainId
    /// @param recipientDestAddress a wallet address of recipient in destination chain
    function transferNFT(address token, uint256 tokenId, uint16 recipientChainId, address recipientDestAddress) public payable {
        TransferData memory transferData;

        if (isWrappedAsset[token]) {
            // if it's wrapper asset, then retrive the original token chainId
            transferData.tokenChainId = WrappedERC721Implementation(token).chainId();
            // get the native contract address
            transferData.tokenAddress = WrappedERC721Implementation(token).nativeContract();
            transferData.srcChainWrappedTokenAddress = addressToBytes32(token);
        } else {
            transferData.tokenChainId = lzChainId;
            transferData.tokenAddress = addressToBytes32(token);
            require(ERC165(token).supportsInterface(type(IERC721).interfaceId), "token must support the ERC721 interface");
            require(ERC165(token).supportsInterface(type(IERC721Metadata).interfaceId), "must support the ERC721-Metadata extension");
        }

        (transferData.symbol, transferData.name, transferData.uri) = _retrieveMetadata(token, tokenId);

        IERC721(token).safeTransferFrom(_msgSender(), address(this), tokenId);
        if (transferData.tokenChainId != lzChainId) {
            WrappedERC721Implementation(token).burn(tokenId);
        }
        transferData.tokenId = tokenId;
        transferData.recipientAddress = addressToBytes32(recipientDestAddress);
        transferData.recipientChainId = recipientChainId;
        transferData.senderAddress = addressToBytes32(_msgSender());
        transferData.senderChainId = lzChainId;

        _transferNFT(transferData);

        emit TransferNFT(
            token,
            bytes32ToAddress(transferData.srcChainWrappedTokenAddress),
            _msgSender(),
            recipientDestAddress,
            transferData.tokenChainId,
            transferData.senderChainId,
            recipientChainId,
            tokenId
        );
    }

    function _determineTokenAndChain() internal view returns (uint16 tokenChainId, address tokenAddress, address inChainWrappedTokenAddress) {}

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

    function _transferNFT(TransferData memory transfer) internal {
        uint16 dstChainId = transfer.recipientChainId;

        bytes memory payload = _encodeTransfer(transfer);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint gasForDestinationLzReceive = 350000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        (uint256 estimatedFee, ) = lzEndpoint.estimateFees(dstChainId, address(this), payload, false, adapterParams);
        require(msg.value >= estimatedFee, "Not enough payable value to cover gas fee in destination address");

        _lzSend(dstChainId, payload, payable(_msgSender()), address(0x0), adapterParams, msg.value);
    }

    function _encodeTransfer(TransferData memory transfer) internal pure returns (bytes memory) {
        require(bytes(transfer.uri).length <= 200, "tokenURI must not exceed 200 bytes");
        bytes memory encoded = abi.encodePacked(
            transfer.tokenAddress,
            transfer.tokenChainId,
            transfer.symbol,
            transfer.name,
            transfer.tokenId,
            transfer.uri,
            transfer.recipientAddress,
            transfer.recipientChainId
        );
        return encoded;
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
