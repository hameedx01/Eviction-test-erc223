pragma solidity ^0.8.30;

interface IERC223Receiver {
    function tokenReceived(address from, uint256 value, bytes calldata data)
        external
        returns (bytes4);
}
