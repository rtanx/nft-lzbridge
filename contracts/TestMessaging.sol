// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "@layerzerolabs/solidity-examples/contracts/lzApp/NonblockingLzApp.sol";

contract TestMessaging is NonblockingLzApp {
    struct Data {
        uint16 sourceChainId;
        address sourceAddress;
        uint64 nonce;
        string message;
    }

    uint256 private gas = 350000;
    uint16 private version = 1;

    mapping(uint16 => Data[]) public dataFromChainId;

    constructor(address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {
        //
    }

    function _nonblockingLzReceive(uint16 _srcChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal override {
        string memory message = abi.decode(_payload, (string));
        address srcAddr = bytesToAddress(_srcAddress);
        Data memory data = Data(_srcChainId, srcAddr, _nonce, message);
        dataFromChainId[_srcChainId].push(data);
    }

    function sendMessage(uint16 _dstChainId, string memory _message) public payable {
        bytes memory payload = abi.encode(_message);
        bytes memory adapterParams = abi.encodePacked(version, gas);

        (uint256 estimatedFee, ) = lzEndpoint.estimateFees(_dstChainId, address(this), payload, false, adapterParams);

        require(msg.value >= estimatedFee, "Not enough payable value to cover gas fee in destination address");

        _lzSend(_dstChainId, payload, payable(msg.sender), address(0x0), adapterParams, msg.value);
    }

    function bytesToAddress(bytes memory data) internal pure returns (address) {
        require(data.length >= 20, "Invalid data length");
        address addr;
        assembly {
            addr := mload(add(data, 20))
        }
        return addr;
    }
}
