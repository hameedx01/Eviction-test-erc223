pragma solidity ^0.8.30;

contract NonReceiver {
    function description() external pure returns (string memory) {
        return "This contract cannot receive ERC-223 tokens";
    }
}
