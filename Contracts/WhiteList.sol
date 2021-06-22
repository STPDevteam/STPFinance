// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.5.0 <0.7.0;


import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract Whitelist is Ownable {

    mapping(address => bool) public whitelist;
    address[] public whitelistedAddresses;

    event AddedToWhitelist(address[] indexed accounts);
    event RemovedFromWhitelist(address indexed account);

    modifier onlyWhitelisted() {
        require(isWhitelisted(msg.sender), 'not in whitelist');
        _;
    }

    constructor () public {
        // default owner in Whitelist
        whitelistedAddresses = [owner()];
        whitelist[owner()] = true;
    }

    function addWhite(address[] memory _addresses) public onlyOwner {
        for (uint i = 0; i < _addresses.length; i++) {
            require(whitelist[_addresses[i]] != true);
            whitelist[_addresses[i]] = true;
            whitelistedAddresses.push(_addresses[i]);
        }
        emit AddedToWhitelist(_addresses);
    }

    function removeWhite(address _address, uint256 _index) public onlyOwner {
        require(_address == whitelistedAddresses[_index]);
        whitelist[_address] = false;
        delete whitelistedAddresses[_index];
        emit RemovedFromWhitelist(_address);
    }

    function getWhitelistedAddresses() public view returns(address[] memory) {
        return whitelistedAddresses;
    }

    function isWhitelisted(address _address) public view returns(bool) {
        return whitelist[_address];
    }
}
